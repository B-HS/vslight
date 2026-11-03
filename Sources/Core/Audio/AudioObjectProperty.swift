import CoreAudio
import Foundation

enum AudioPropertyError: Error, LocalizedError {
    case status(OSStatus)
    case missingValue

    var errorDescription: String? {
        switch self {
        case let .status(status):
            "CoreAudio 오류 (\(status))"
        case .missingValue:
            "오디오 속성 값을 읽지 못했습니다."
        }
    }
}

let systemAudioObject = AudioObjectID(kAudioObjectSystemObject)

func audioPropertyAddress(
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
    element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
}

enum AudioProperty {
    static func has(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        return AudioObjectHasProperty(object, &address)
    }

    static func isSettable(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var settable: DarwinBoolean = false
        let status = AudioObjectIsPropertySettable(object, &address, &settable)
        return status == noErr && settable.boolValue
    }

    static func get<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, defaultValue: T) throws -> T {
        var address = address
        var size = UInt32(MemoryLayout<T>.size)
        var value = defaultValue
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else {
            throw AudioPropertyError.status(status)
        }
        return value
    }

    static func getString(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) throws -> String {
        var address = address
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else {
            throw AudioPropertyError.missingValue
        }
        return value as String
    }

    static func getArray(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) throws -> [AudioObjectID] {
        var address = address
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size)
        guard status == noErr else {
            throw AudioPropertyError.status(status)
        }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else {
            return []
        }
        var values = [AudioObjectID](repeating: 0, count: count)
        status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &values)
        guard status == noErr else {
            throw AudioPropertyError.status(status)
        }
        return values
    }

    static func set<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, value: T) throws {
        var address = address
        var value = value
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<T>.size), pointer)
        }
        guard status == noErr else {
            throw AudioPropertyError.status(status)
        }
    }

    static func outputChannelCount(_ device: AudioObjectID) -> Int {
        var address = audioPropertyAddress(kAudioDevicePropertyStreamConfiguration, scope: kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else {
            return 0
        }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr else {
            return 0
        }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
