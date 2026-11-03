#include <aspl/Client.hpp>
#include <aspl/Context.hpp>
#include <aspl/Device.hpp>
#include <aspl/DoubleBuffer.hpp>
#include <aspl/Driver.hpp>
#include <aspl/IORequestHandler.hpp>
#include <aspl/Plugin.hpp>
#include <aspl/Stream.hpp>
#include <aspl/Tracer.hpp>

#include <CoreAudio/AudioServerPlugIn.h>
#include <CoreFoundation/CoreFoundation.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstring>
#include <limits>
#include <string>
#include <vector>

namespace {

constexpr UInt32 kSampleRate = 48000;
constexpr UInt32 kChannelCount = 2;
constexpr UInt32 kZeroTimeStampPeriod = 512;
constexpr UInt32 kMaxFrames = 8192;
constexpr size_t kRingCapacityFrames = kSampleRate * 2;
constexpr AudioObjectPropertySelector kAppVolumesSelector = 'apvl';

aspl::StreamParameters MakeStreamParameters(aspl::Direction direction)
{
    aspl::StreamParameters parameters;
    parameters.Direction = direction;
    parameters.Format.mSampleRate = static_cast<Float64>(kSampleRate);
    parameters.Format.mFormatID = kAudioFormatLinearPCM;
    parameters.Format.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    parameters.Format.mBitsPerChannel = 32;
    parameters.Format.mChannelsPerFrame = kChannelCount;
    parameters.Format.mBytesPerFrame = sizeof(Float32) * kChannelCount;
    parameters.Format.mFramesPerPacket = 1;
    parameters.Format.mBytesPerPacket = sizeof(Float32) * kChannelCount;
    return parameters;
}

struct GainEntry
{
    std::string bundleID;
    pid_t pid = 0;
    float volume = 1.0f;
    bool muted = false;
};

class DriverHandler final : public aspl::ControlRequestHandler, public aspl::IORequestHandler
{
public:
    DriverHandler()
        : ring_(kRingCapacityFrames * kChannelCount, 0.0f)
        , scratch_(kMaxFrames * kChannelCount, 0.0f)
    {
    }

    OSStatus OnStartIO() override
    {
        ResetIO();
        return kAudioHardwareNoError;
    }

    void OnStopIO() override
    {
        FlushScratch();
    }

    void OnProcessClientOutput(const std::shared_ptr<aspl::Client>& client,
        const std::shared_ptr<aspl::Stream>& stream,
        Float64 zeroTimestamp,
        Float64 timestamp,
        Float32* frames,
        UInt32 frameCount,
        UInt32 channelCount) override
    {
        (void)zeroTimestamp;
        (void)timestamp;

        if (stream) {
            stream->ApplyProcessing(frames, frameCount, channelCount);
        }

        float volume = 1.0f;
        bool muted = false;
        {
            aspl::DoubleBuffer<std::vector<GainEntry>>::ReadLock lock(gains_);
            const auto& entries = lock.GetReference();
            const std::string bundleID = client ? client->GetBundleID() : std::string();
            const pid_t pid = client ? client->GetProcessID() : 0;

            for (const auto& entry : entries) {
                const bool matchesBundle = !entry.bundleID.empty() && entry.bundleID == bundleID;
                const bool matchesPid = entry.bundleID.empty() && entry.pid != 0 && entry.pid == pid;
                if (matchesBundle || matchesPid) {
                    volume = entry.volume;
                    muted = entry.muted;
                    break;
                }
            }
        }

        if (muted || volume <= 0.0f) {
            std::memset(frames, 0, sizeof(Float32) * frameCount * channelCount);
            return;
        }
        if (volume != 1.0f) {
            const size_t sampleCount = static_cast<size_t>(frameCount) * channelCount;
            for (size_t index = 0; index < sampleCount; ++index) {
                frames[index] *= volume;
            }
        }
    }

    void OnWriteClientOutput(const std::shared_ptr<aspl::Client>& client,
        const std::shared_ptr<aspl::Stream>& stream,
        Float64 zeroTimestamp,
        Float64 timestamp,
        const Float32* frames,
        UInt32 frameCount,
        UInt32 channelCount) override
    {
        (void)client;
        (void)stream;
        (void)zeroTimestamp;

        if (frameCount == 0 || channelCount == 0) {
            return;
        }

        if (!scratchActive_ || scratchTimestamp_ != timestamp) {
            FlushScratch();
            scratchTimestamp_ = timestamp;
            scratchActive_ = true;
            scratchFrames_ = 0;
        }

        if (scratchFrames_ + frameCount > kMaxFrames) {
            FlushScratch();
            scratchTimestamp_ = timestamp;
            scratchActive_ = true;
            scratchFrames_ = 0;
        }

        if (scratchFrames_ == 0) {
            const size_t clearCount = std::min<size_t>(
                scratch_.size(),
                static_cast<size_t>(frameCount) * kChannelCount);
            std::fill(scratch_.begin(), scratch_.begin() + clearCount, 0.0f);
        }

        const UInt32 copyChannels = std::min(channelCount, kChannelCount);
        for (UInt32 frame = 0; frame < frameCount; ++frame) {
            const size_t destination = (static_cast<size_t>(scratchFrames_ + frame) * kChannelCount);
            const size_t source = static_cast<size_t>(frame) * channelCount;
            for (UInt32 channel = 0; channel < copyChannels; ++channel) {
                scratch_[destination + channel] += frames[source + channel];
            }
        }
        scratchFrames_ += frameCount;
    }

    void OnReadClientInput(const std::shared_ptr<aspl::Client>& client,
        const std::shared_ptr<aspl::Stream>& stream,
        Float64 zeroTimestamp,
        Float64 timestamp,
        void* bytes,
        UInt32 bytesCount) override
    {
        (void)client;
        (void)stream;
        (void)zeroTimestamp;
        (void)timestamp;

        auto* destination = static_cast<Float32*>(bytes);
        const UInt32 frameCount = bytesCount / (sizeof(Float32) * kChannelCount);
        std::memset(destination, 0, bytesCount);

        UInt64 startFrame = readFrame_.load(std::memory_order_acquire);
        const UInt64 writeFrame = writeFrame_.load(std::memory_order_acquire);
        if (startFrame == kInvalidFrame || startFrame > writeFrame) {
            readFrame_.store(writeFrame, std::memory_order_release);
            startFrame = writeFrame;
        }
        if (startFrame >= writeFrame) {
            return;
        }

        if (writeFrame - startFrame > kRingCapacityFrames) {
            startFrame = writeFrame - kRingCapacityFrames;
        }

        const UInt64 available = writeFrame - startFrame;
        const UInt32 framesToRead = static_cast<UInt32>(std::min<UInt64>(frameCount, available));
        for (UInt32 frame = 0; frame < framesToRead; ++frame) {
            const size_t source = static_cast<size_t>((startFrame + frame) % kRingCapacityFrames) * kChannelCount;
            const size_t target = static_cast<size_t>(frame) * kChannelCount;
            for (UInt32 channel = 0; channel < kChannelCount; ++channel) {
                destination[target + channel] = ring_[source + channel];
            }
        }
        readFrame_.store(startFrame + framesToRead, std::memory_order_release);
    }

    CFPropertyListRef CopyAppVolumes() const
    {
        CFMutableArrayRef array = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
        if (!array) {
            return nullptr;
        }

        aspl::DoubleBuffer<std::vector<GainEntry>>::ReadLock lock(gains_);
        for (const auto& entry : lock.GetReference()) {
            CFMutableDictionaryRef dictionary = CFDictionaryCreateMutable(
                kCFAllocatorDefault,
                0,
                &kCFTypeDictionaryKeyCallBacks,
                &kCFTypeDictionaryValueCallBacks);
            if (!dictionary) {
                continue;
            }

            if (!entry.bundleID.empty()) {
                CFStringRef bundleID = CFStringCreateWithCString(
                    kCFAllocatorDefault,
                    entry.bundleID.c_str(),
                    kCFStringEncodingUTF8);
                if (bundleID) {
                    CFDictionarySetValue(dictionary, CFSTR("bundleID"), bundleID);
                    CFRelease(bundleID);
                }
            }

            if (entry.pid != 0) {
                CFNumberRef pid = CFNumberCreate(
                    kCFAllocatorDefault,
                    kCFNumberIntType,
                    &entry.pid);
                if (pid) {
                    CFDictionarySetValue(dictionary, CFSTR("pid"), pid);
                    CFRelease(pid);
                }
            }

            Float32 volume = entry.volume;
            CFNumberRef volumeNumber = CFNumberCreate(
                kCFAllocatorDefault,
                kCFNumberFloat32Type,
                &volume);
            if (volumeNumber) {
                CFDictionarySetValue(dictionary, CFSTR("volume"), volumeNumber);
                CFRelease(volumeNumber);
            }

            CFDictionarySetValue(
                dictionary,
                CFSTR("muted"),
                entry.muted ? kCFBooleanTrue : kCFBooleanFalse);

            CFArrayAppendValue(array, dictionary);
            CFRelease(dictionary);
        }

        return array;
    }

    void SetAppVolumes(CFPropertyListRef value)
    {
        std::vector<GainEntry> entries;
        if (!value || CFGetTypeID(value) != CFArrayGetTypeID()) {
            gains_.Set(std::move(entries));
            return;
        }

        const CFArrayRef array = static_cast<CFArrayRef>(value);
        const CFIndex count = CFArrayGetCount(array);
        entries.reserve(static_cast<size_t>(count));

        for (CFIndex index = 0; index < count; ++index) {
            CFTypeRef item = CFArrayGetValueAtIndex(array, index);
            if (!item || CFGetTypeID(item) != CFDictionaryGetTypeID()) {
                continue;
            }
            const CFDictionaryRef dictionary = static_cast<CFDictionaryRef>(item);
            GainEntry entry;

            CFTypeRef bundleID = CFDictionaryGetValue(dictionary, CFSTR("bundleID"));
            if (bundleID && CFGetTypeID(bundleID) == CFStringGetTypeID()) {
                char buffer[1024];
                if (CFStringGetCString(
                        static_cast<CFStringRef>(bundleID),
                        buffer,
                        sizeof(buffer),
                        kCFStringEncodingUTF8)) {
                    entry.bundleID = buffer;
                }
            }

            CFTypeRef pid = CFDictionaryGetValue(dictionary, CFSTR("pid"));
            if (pid && CFGetTypeID(pid) == CFNumberGetTypeID()) {
                int value = 0;
                if (CFNumberGetValue(static_cast<CFNumberRef>(pid), kCFNumberIntType, &value)) {
                    entry.pid = value;
                }
            }

            CFTypeRef volume = CFDictionaryGetValue(dictionary, CFSTR("volume"));
            if (volume && CFGetTypeID(volume) == CFNumberGetTypeID()) {
                double value = 1.0;
                if (CFNumberGetValue(static_cast<CFNumberRef>(volume), kCFNumberFloat64Type, &value)) {
                    entry.volume = static_cast<float>(std::clamp(value, 0.0, 1.0));
                }
            }

            CFTypeRef muted = CFDictionaryGetValue(dictionary, CFSTR("muted"));
            if (muted && CFGetTypeID(muted) == CFBooleanGetTypeID()) {
                entry.muted = CFBooleanGetValue(static_cast<CFBooleanRef>(muted));
            }

            if (entry.bundleID.empty() && entry.pid == 0) {
                continue;
            }
            entries.push_back(std::move(entry));
        }

        gains_.Set(std::move(entries));
    }

private:
    static constexpr UInt64 kInvalidFrame = std::numeric_limits<UInt64>::max();

    void ResetIO()
    {
        writeFrame_.store(0, std::memory_order_release);
        readFrame_.store(kInvalidFrame, std::memory_order_release);
        scratchTimestamp_ = 0.0;
        scratchFrames_ = 0;
        scratchActive_ = false;
        std::fill(ring_.begin(), ring_.end(), 0.0f);
        std::fill(scratch_.begin(), scratch_.end(), 0.0f);
    }

    void FlushScratch()
    {
        if (!scratchActive_ || scratchFrames_ == 0) {
            scratchActive_ = false;
            scratchFrames_ = 0;
            return;
        }

        const UInt64 startFrame = static_cast<UInt64>(std::llround(scratchTimestamp_));
        for (UInt32 frame = 0; frame < scratchFrames_; ++frame) {
            const size_t destination = static_cast<size_t>((startFrame + frame) % kRingCapacityFrames) * kChannelCount;
            const size_t source = static_cast<size_t>(frame) * kChannelCount;
            for (UInt32 channel = 0; channel < kChannelCount; ++channel) {
                ring_[destination + channel] = scratch_[source + channel];
            }
        }

        writeFrame_.store(startFrame + scratchFrames_, std::memory_order_release);
        if (readFrame_.load(std::memory_order_acquire) == kInvalidFrame) {
            readFrame_.store(startFrame, std::memory_order_release);
        }
        scratchActive_ = false;
        scratchFrames_ = 0;
    }

    std::vector<float> ring_;
    std::vector<float> scratch_;
    std::atomic<UInt64> writeFrame_ = 0;
    std::atomic<UInt64> readFrame_ = kInvalidFrame;
    aspl::DoubleBuffer<std::vector<GainEntry>> gains_;

    Float64 scratchTimestamp_ = 0.0;
    UInt32 scratchFrames_ = 0;
    bool scratchActive_ = false;
};

std::shared_ptr<aspl::Driver> CreateDriver()
{
    auto tracer = std::make_shared<aspl::Tracer>(aspl::Tracer::Mode::Noop);
    auto context = std::make_shared<aspl::Context>(tracer);

    aspl::DeviceParameters deviceParameters;
    deviceParameters.Name = "VSLight Audio";
    deviceParameters.Manufacturer = "VSLight";
    deviceParameters.DeviceUID = "com.bhs.vslight.driver.device";
    deviceParameters.ModelUID = "com.bhs.vslight.driver";
    deviceParameters.SampleRate = kSampleRate;
    deviceParameters.ChannelCount = kChannelCount;
    deviceParameters.ZeroTimeStampPeriod = kZeroTimeStampPeriod;
    deviceParameters.Latency = 0;
    deviceParameters.SafetyOffset = 0;
    deviceParameters.EnableMixing = false;
    deviceParameters.CanBeDefault = true;
    deviceParameters.CanBeDefaultForSystemSounds = true;

    auto device = std::make_shared<aspl::Device>(context, deviceParameters);
    auto handler = std::make_shared<DriverHandler>();

    device->AddStreamWithControlsAsync(MakeStreamParameters(aspl::Direction::Output));
    device->SetControlHandler(handler);
    device->SetIOHandler(handler);
    device->RegisterCustomProperty(
        kAppVolumesSelector,
        std::function<CFPropertyListRef()>([handler]() {
            return handler->CopyAppVolumes();
        }),
        std::function<void(CFPropertyListRef)>([handler](CFPropertyListRef value) {
            handler->SetAppVolumes(value);
        }));

    aspl::DeviceParameters inputParameters;
    inputParameters.Name = "VSLight Audio Input";
    inputParameters.Manufacturer = "VSLight";
    inputParameters.DeviceUID = "com.bhs.vslight.driver.input";
    inputParameters.ModelUID = "com.bhs.vslight.driver";
    inputParameters.SampleRate = kSampleRate;
    inputParameters.ChannelCount = kChannelCount;
    inputParameters.ZeroTimeStampPeriod = kZeroTimeStampPeriod;
    inputParameters.EnableMixing = false;
    inputParameters.CanBeDefault = false;
    inputParameters.CanBeDefaultForSystemSounds = false;

    auto inputDevice = std::make_shared<aspl::Device>(context, inputParameters);
    inputDevice->AddStreamAsync(MakeStreamParameters(aspl::Direction::Input));
    inputDevice->SetControlHandler(handler);
    inputDevice->SetIOHandler(handler);

    auto plugin = std::make_shared<aspl::Plugin>(context);
    plugin->AddDevice(device);
    plugin->AddDevice(inputDevice);

    return std::make_shared<aspl::Driver>(context, plugin);
}

} // namespace

extern "C" void* VSLightAudioDriverEntryPoint(CFAllocatorRef allocator, CFUUIDRef typeUUID)
{
    (void)allocator;

    if (!typeUUID || !CFEqual(typeUUID, kAudioServerPlugInTypeUUID)) {
        return nullptr;
    }

    static std::shared_ptr<aspl::Driver> driver = CreateDriver();
    return driver->GetReference();
}
