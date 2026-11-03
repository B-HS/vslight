import CoreAudio
import Foundation

func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

func read<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ initial: T) -> T? {
    var address = address
    var size = UInt32(MemoryLayout<T>.size)
    var value = initial
    let status = withUnsafeMutablePointer(to: &value) { pointer in
        AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer)
    }
    return status == noErr ? value : nil
}

func readString(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> String? {
    var address = address
    var size = UInt32(MemoryLayout<CFString?>.size)
    var value: CFString?
    let status = withUnsafeMutablePointer(to: &value) { pointer in
        AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer)
    }
    guard status == noErr, let value else { return nil }
    return value as String
}

func settable(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
    var address = address
    var value: DarwinBoolean = false
    let status = AudioObjectIsPropertySettable(object, &address, &value)
    return status == noErr && value.boolValue
}

let system = AudioObjectID(kAudioObjectSystemObject)
guard let device: AudioObjectID = read(system, address(kAudioHardwarePropertyDefaultOutputDevice), 0),
      device != kAudioObjectUnknown
else {
    print("기본 출력 장치를 찾지 못했습니다.")
    exit(1)
}

let name = readString(device, address(kAudioObjectPropertyName)) ?? "이름 없음"
let uid = readString(device, address(kAudioDevicePropertyDeviceUID)) ?? "UID 없음"
let volumeAddress = address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput)
let muteAddress = address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
let volume: Float = read(device, volumeAddress, 0) ?? -1
let mute: UInt32 = read(device, muteAddress, 0) ?? 0

print("장치: \(name)")
print("UID: \(uid)")
print("볼륨: \(volume)")
print("볼륨 설정 가능: \(settable(device, volumeAddress))")
print("뮤트: \(mute)")
print("뮤트 설정 가능: \(settable(device, muteAddress))")

var streamAddress = address(kAudioDevicePropertyStreamConfiguration, scope: kAudioDevicePropertyScopeOutput)
var size: UInt32 = 0
if AudioObjectGetPropertyDataSize(device, &streamAddress, 0, nil, &size) == noErr, size > 0 {
    let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { raw.deallocate() }
    if AudioObjectGetPropertyData(device, &streamAddress, 0, nil, &size, raw) == noErr {
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        let channels = list.reduce(0) { $0 + Int($1.mNumberChannels) }
        print("출력 채널 수: \(channels)")
        for index in 1...max(channels, 1) {
            let channelAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: AudioObjectPropertyElement(index)
            )
            let channelVolume: Float = read(device, channelAddress, 0) ?? -1
            print("채널 \(index) 볼륨: \(channelVolume), 설정 가능: \(settable(device, channelAddress))")
        }
    }
}
