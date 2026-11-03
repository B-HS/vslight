import CoreAudio
import XCTest
@testable import VSLight

final class AudioDeviceTests: XCTestCase {
    func testAggregateDeviceAppearsInOutputList() throws {
        guard let defaultID = AudioDevice.defaultOutputID() else {
            throw XCTSkip("기본 출력 장치가 없습니다.")
        }
        let builtInUID = try AudioProperty.getString(
            defaultID,
            audioPropertyAddress(kAudioDevicePropertyDeviceUID)
        )
        let aggregateUID = "com.bhs.vslight.test-\(UUID().uuidString)"
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "VSLight Test Output",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: builtInUID,
            kAudioAggregateDeviceClockDeviceKey: builtInUID,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: builtInUID]
            ],
            kAudioAggregateDeviceIsStackedKey: 0
        ]

        var aggregateID: AudioObjectID = 0
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID)
        guard status == noErr else {
            throw XCTSkip("집계 장치를 만들지 못했습니다. status=\(status)")
        }
        defer {
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }

        let devices = AudioDevice.allOutputDevices()
        XCTAssertTrue(
            devices.contains { $0.uid == aggregateUID },
            "집계 장치가 출력 장치 목록에 없습니다. count=\(devices.count)"
        )
        XCTAssertGreaterThanOrEqual(devices.count, 2)
    }
}
