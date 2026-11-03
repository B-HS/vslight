import Carbon
import XCTest
@testable import VSLight

final class HotkeyTests: XCTestCase {
    func testDisplayString() {
        let hotkey = Hotkey(keyCode: 0, modifiers: UInt32(cmdKey))
        XCTAssertEqual(hotkey.displayString, "⌘A")
        XCTAssertTrue(hotkey.isValid)
    }

    func testModifierConversion() {
        let flags: NSEvent.ModifierFlags = [.command, .option]
        let converted = Hotkey.carbonModifiers(from: flags)
        XCTAssertEqual(converted, UInt32(cmdKey | optionKey))
    }

    func testModifierOnlyHotkeyIsInvalid() {
        XCTAssertFalse(Hotkey(keyCode: 12, modifiers: 0).isValid)
    }

    func testPresetRoundTrip() throws {
        let preset = VolumePreset(
            name: "테스트",
            volume: 0.637,
            deviceUID: "uid-1",
            hotkey: Hotkey(keyCode: 18, modifiers: UInt32(controlKey | optionKey))
        )
        let data = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(VolumePreset.self, from: data)
        XCTAssertEqual(decoded, preset)
        XCTAssertEqual(decoded.volumeText, "63.7")
    }
}
