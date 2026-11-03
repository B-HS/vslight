import CoreAudio
import Foundation
import Observation
import os

private final class LoopbackBuffer: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private let capacityFrames: Int
    private let channels = 2
    private var storage: [Float]
    private var writeIndex = 0
    private var readIndex = 0

    init(capacityFrames: Int) {
        self.capacityFrames = capacityFrames
        storage = [Float](repeating: 0, count: capacityFrames * channels)
    }

    func write(_ data: UnsafePointer<Float>, frames: Int, channels inputChannels: Int) {
        guard frames > 0, inputChannels > 0 else {
            return
        }
        lock.lock()
        defer { lock.unlock() }
        for frame in 0..<frames {
            if writeIndex - readIndex >= capacityFrames {
                readIndex += 1
            }
            let destination = (writeIndex % capacityFrames) * channels
            let source = frame * inputChannels
            storage[destination] = data[source]
            storage[destination + 1] = inputChannels > 1 ? data[source + 1] : data[source]
            writeIndex += 1
        }
    }

    func read(into data: UnsafeMutablePointer<Float>, frames: Int, channels outputChannels: Int) {
        guard frames > 0, outputChannels > 0 else {
            return
        }
        lock.lock()
        defer { lock.unlock() }
        let available = writeIndex - readIndex
        let framesToRead = min(frames, max(0, available))
        for frame in 0..<framesToRead {
            let source = (readIndex % capacityFrames) * channels
            let destination = frame * outputChannels
            data[destination] = storage[source]
            if outputChannels > 1 {
                data[destination + 1] = storage[source + 1]
            }
            readIndex += 1
        }
        if framesToRead < frames {
            let missing = (frames - framesToRead) * outputChannels
            memset(data.advanced(by: framesToRead * outputChannels), 0, missing * MemoryLayout<Float>.size)
        }
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        storage = [Float](repeating: 0, count: capacityFrames * channels)
        writeIndex = 0
        readIndex = 0
    }
}

enum LoopbackError: LocalizedError {
    case driverMissing
    case outputMissing
    case ioCreationFailed(OSStatus)
    case ioStartFailed(OSStatus)
    case defaultDeviceFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .driverMissing:
            String(localized: "VSLight 오디오 드라이버를 찾지 못했습니다.")
        case .outputMissing:
            String(localized: "출력 장치를 찾지 못했습니다.")
        case let .ioCreationFailed(status):
            String(localized: "오디오 루프백을 만들지 못했습니다.") + " (\(status))"
        case let .ioStartFailed(status):
            String(localized: "오디오 루프백을 시작하지 못했습니다.") + " (\(status))"
        case let .defaultDeviceFailed(status):
            String(localized: "출력 장치를 전환하지 못했습니다.") + " (\(status))"
        }
    }
}

@MainActor
@Observable
final class LoopbackEngine {
    private(set) var isRunning = false
    private(set) var lastError: String?

    private let buffer = LoopbackBuffer(capacityFrames: 48000 * 2)
    private let queue = DispatchQueue(label: "com.bhs.vslight.loopback", qos: .userInteractive)
    private var driverDeviceID: AudioObjectID = kAudioObjectUnknown
    private var outputDeviceID: AudioObjectID = kAudioObjectUnknown
    private var driverProc: AudioDeviceIOProcID?
    private var outputProc: AudioDeviceIOProcID?
    private var previousDefaultUID: String?
    private var previousDriverVolume: Float?

    func start(driverUID: String, outputUID: String) throws {
        guard !isRunning else {
            return
        }
        lastError = nil
        buffer.reset()

        guard let driver = AudioDevice.allOutputDevices().first(where: { $0.uid == driverUID }) else {
            throw LoopbackError.driverMissing
        }
        guard let output = AudioDevice.allOutputDevices().first(where: { $0.uid == outputUID }) else {
            throw LoopbackError.outputMissing
        }

        driverDeviceID = driver.id
        outputDeviceID = output.id
        previousDefaultUID = AudioDevice.defaultOutputID().flatMap { id in
            AudioDevice.allOutputDevices().first(where: { $0.id == id })?.uid
        }
        previousDriverVolume = readVolume(driver.id)

        setVolume(driver.id, 1.0)

        do {
            try createDriverProc()
            try createOutputProc()
            try startProcs()
            try selectDriverAsDefault()
            isRunning = true
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        guard driverDeviceID != kAudioObjectUnknown || outputDeviceID != kAudioObjectUnknown else {
            isRunning = false
            return
        }

        if let previousDefaultUID,
           let previous = AudioDevice.allOutputDevices().first(where: { $0.uid == previousDefaultUID }) {
            var value = previous.id
            try? AudioProperty.set(
                systemAudioObject,
                audioPropertyAddress(kAudioHardwarePropertyDefaultOutputDevice),
                value: value
            )
            value = 0
        }

        if let outputProc {
            AudioDeviceStop(outputDeviceID, outputProc)
            AudioDeviceDestroyIOProcID(outputDeviceID, outputProc)
        }
        if let driverProc {
            AudioDeviceStop(driverDeviceID, driverProc)
            AudioDeviceDestroyIOProcID(driverDeviceID, driverProc)
        }
        outputProc = nil
        driverProc = nil

        if let previousDriverVolume {
            setVolume(driverDeviceID, previousDriverVolume)
        }

        buffer.reset()
        driverDeviceID = kAudioObjectUnknown
        outputDeviceID = kAudioObjectUnknown
        previousDefaultUID = nil
        previousDriverVolume = nil
        isRunning = false
    }

    nonisolated private static func makeDriverIOBlock(buffer: LoopbackBuffer) -> AudioDeviceIOBlock {
        { _, inputData, _, _, _ in
            let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
            guard let bufferList = list.first,
                  let data = bufferList.mData
            else {
                return
            }
            let frames = Int(bufferList.mDataByteSize) / (MemoryLayout<Float>.size * 2)
            buffer.write(
                data.assumingMemoryBound(to: Float.self),
                frames: frames,
                channels: Int(bufferList.mNumberChannels)
            )
        }
    }

    nonisolated private static func makeOutputIOBlock(buffer: LoopbackBuffer) -> AudioDeviceIOBlock {
        { _, _, _, outputData, _ in
            let list = UnsafeMutableAudioBufferListPointer(outputData)
            guard let bufferList = list.first,
                  let data = bufferList.mData
            else {
                return
            }
            let frames = Int(bufferList.mDataByteSize) / (MemoryLayout<Float>.size * 2)
            buffer.read(
                into: data.assumingMemoryBound(to: Float.self),
                frames: frames,
                channels: Int(bufferList.mNumberChannels)
            )
        }
    }

    private func createDriverProc() throws {
        let block = Self.makeDriverIOBlock(buffer: buffer)
        var proc: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&proc, driverDeviceID, queue, block)
        guard status == noErr, let proc else {
            throw LoopbackError.ioCreationFailed(status)
        }
        driverProc = proc
    }

    private func createOutputProc() throws {
        let block = Self.makeOutputIOBlock(buffer: buffer)
        var proc: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&proc, outputDeviceID, queue, block)
        guard status == noErr, let proc else {
            throw LoopbackError.ioCreationFailed(status)
        }
        outputProc = proc
    }

    private func startProcs() throws {
        guard let outputProc, let driverProc else {
            throw LoopbackError.ioCreationFailed(-1)
        }
        var status = AudioDeviceStart(outputDeviceID, outputProc)
        guard status == noErr else {
            throw LoopbackError.ioStartFailed(status)
        }
        status = AudioDeviceStart(driverDeviceID, driverProc)
        guard status == noErr else {
            AudioDeviceStop(outputDeviceID, outputProc)
            throw LoopbackError.ioStartFailed(status)
        }
    }

    private func selectDriverAsDefault() throws {
        try AudioProperty.set(
            systemAudioObject,
            audioPropertyAddress(kAudioHardwarePropertyDefaultOutputDevice),
            value: driverDeviceID
        )
    }

    private func readVolume(_ device: AudioObjectID) -> Float? {
        let address = audioPropertyAddress(
            kAudioDevicePropertyVolumeScalar,
            scope: kAudioDevicePropertyScopeOutput
        )
        return try? AudioProperty.get(device, address, defaultValue: Float(0))
    }

    private func setVolume(_ device: AudioObjectID, _ value: Float) {
        guard device != kAudioObjectUnknown else {
            return
        }
        let address = audioPropertyAddress(
            kAudioDevicePropertyVolumeScalar,
            scope: kAudioDevicePropertyScopeOutput
        )
        try? AudioProperty.set(device, address, value: min(max(value, 0), 1))
    }
}
