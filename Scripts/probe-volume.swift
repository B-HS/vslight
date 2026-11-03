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

func write<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ value: T) -> OSStatus {
    var address = address
    var value = value
    return withUnsafeMutablePointer(to: &value) { pointer in
        AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<T>.size), pointer)
    }
}

let system = AudioObjectID(kAudioObjectSystemObject)
guard let device: AudioObjectID = read(system, address(kAudioHardwarePropertyDefaultOutputDevice), 0),
      device != kAudioObjectUnknown
else {
    print("기본 출력 장치를 찾지 못했습니다.")
    exit(1)
}

let volumeAddress = address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput)
let original: Float = read(device, volumeAddress, 0) ?? 0
let target: Float = 0.1373
defer {
    _ = write(device, volumeAddress, original)
    print("복원: \(original)")
}

let status = write(device, volumeAddress, target)
let readBack: Float = read(device, volumeAddress, 0) ?? -1
print("설정 요청: \(target), 상태: \(status)")
print("되읽기: \(readBack), 차이: \(abs(Double(readBack - target)))")
