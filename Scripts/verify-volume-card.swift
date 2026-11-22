import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class AudioSystem {
    var volume = 0.5
    var isMuted = false
    var canSetMute = true
    var canSetVolume = true
}

struct AppSettings {
    var decimals = 1
}

@MainActor
@Observable
final class SettingsStore {
    var settings = AppSettings()
}

@MainActor
@Observable
final class AppModel {
    let audio = AudioSystem()
    let store = SettingsStore()
    @ObservationIgnored var appliedVolumes: [Double] = []

    func setVolume(_ value: Double) {
        let clamped = min(max(value, 0), 1)
        appliedVolumes.append(clamped)
        audio.volume = clamped
        DispatchQueue.main.async { [audio] in
            audio.volume = Double(Float(clamped))
        }
    }

    func toggleMute() {
        audio.isMuted.toggle()
    }
}

private let cardOuterPadding: CGFloat = 12
private let cardInnerPadding: CGFloat = 12
private let sliderHitHeight: CGFloat = 20

@MainActor
final class VolumeCardHarness {
    private let model = AppModel()
    private let window: NSWindow
    private var failures: [String] = []

    init() {
        let hostingView = NSHostingView(
            rootView: VolumeCardView()
                .environment(model)
                .padding(cardOuterPadding)
                .frame(width: 304)
        )
        window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: 80, y: 80), size: hostingView.fittingSize),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func run() async -> [String] {
        await settle()
        guard textField != nil, sliderFrame != nil else {
            dumpHierarchy(window.contentView, depth: 0)
            return ["TextField 또는 Slider 를 찾지 못했습니다."]
        }
        print("key window: \(window.isKeyWindow)")

        await sliderWhileFocused()
        await sliderKeepsUpdatingAfterRelease()
        await externalChangeWhileFocused()
        await typeAndSubmit()
        await typeThenSlider()
        await typeThenBlur()
        await focusThenBlurWithoutEdit()
        return failures
    }

    private func sliderWhileFocused() async {
        await reset(volume: 0.5, decimals: 1)
        await focusField()
        check("입력란 클릭 시 포커스", isFieldFocused)
        await clickSlider(at: 0.7)
        let volume = model.audio.volume
        check("슬라이더 변경이 볼륨에 적용됨", abs(volume - 0.5) > 0.05, "volume=\(volume)")
        check("포커스 중 슬라이더 변경이 숫자에 반영됨", fieldText == expectedText, "field=\(fieldText) expected=\(expectedText)")
        check("슬라이더 변경 후 포커스 해제", !isFieldFocused)
        check("슬라이더 값이 이전 숫자로 되돌려지지 않음", model.appliedVolumes.allSatisfy { abs($0 - 0.5) > 0.05 }, "applied=\(model.appliedVolumes)")
    }

    private func sliderKeepsUpdatingAfterRelease() async {
        await reset(volume: 0.5, decimals: 1)
        await focusField()
        await clickSlider(at: 0.7)
        await clickSlider(at: 0.2)
        check("포커스 해제 후에도 숫자가 계속 반영됨", fieldText == expectedText, "field=\(fieldText) expected=\(expectedText)")
        window.makeFirstResponder(nil)
        await settle()
        check("창 포커스 이동 후에도 슬라이더 값 유지", abs(model.audio.volume - 0.5) > 0.05 && fieldText == expectedText, "volume=\(model.audio.volume) field=\(fieldText)")
    }

    private func externalChangeWhileFocused() async {
        await reset(volume: 0.5, decimals: 1)
        await focusField()
        model.setVolume(0.25)
        await settle()
        check("포커스 중 외부 볼륨 변경이 숫자에 반영됨", fieldText == "25.0", "field=\(fieldText)")
        check("외부 볼륨 변경 후 포커스 해제", !isFieldFocused)
        check("외부 변경 뒤 추가 적용 없음", model.appliedVolumes == [0.25], "applied=\(model.appliedVolumes)")
    }

    private func typeAndSubmit() async {
        await reset(volume: 0.5, decimals: 1)
        await focusField()
        type("30")
        await settle()
        pressReturn()
        await settle()
        check("입력 후 Return 으로 볼륨 적용", abs(model.audio.volume - 0.3) < 0.0001, "volume=\(model.audio.volume)")
        check("Return 후 숫자 표시", fieldText == "30.0", "field=\(fieldText)")
        check("Return 후 포커스 해제", !isFieldFocused)
        await clickSlider(at: 0.8)
        check("Return 후 슬라이더 변경이 숫자에 반영됨", fieldText == expectedText, "field=\(fieldText) expected=\(expectedText)")
    }

    private func typeThenSlider() async {
        await reset(volume: 0.5, decimals: 1)
        await focusField()
        type("30")
        await settle()
        await clickSlider(at: 0.7)
        check("입력 도중 슬라이더를 움직이면 슬라이더 값이 유지됨", abs(model.audio.volume - 0.3) > 0.05 && abs(model.audio.volume - 0.5) > 0.05, "volume=\(model.audio.volume) applied=\(model.appliedVolumes)")
        check("입력 도중 슬라이더 변경이 숫자에 반영됨", fieldText == expectedText, "field=\(fieldText) expected=\(expectedText)")
    }

    private func typeThenBlur() async {
        await reset(volume: 0.5, decimals: 1)
        await focusField()
        type("30")
        await settle()
        window.makeFirstResponder(nil)
        await settle()
        check("입력 후 포커스를 잃으면 입력값 적용", abs(model.audio.volume - 0.3) < 0.0001 && fieldText == "30.0", "volume=\(model.audio.volume) field=\(fieldText)")
    }

    private func focusThenBlurWithoutEdit() async {
        await reset(volume: 0.637, decimals: 0)
        await focusField()
        window.makeFirstResponder(nil)
        await settle()
        check("수정 없이 포커스를 잃으면 볼륨을 바꾸지 않음", model.appliedVolumes.isEmpty, "applied=\(model.appliedVolumes)")
    }

    private var textField: NSTextField? {
        find(NSTextField.self, in: window.contentView)
    }

    private var sliderFrame: NSRect? {
        guard let bounds = window.contentView?.bounds else {
            return nil
        }
        let inset = cardOuterPadding + cardInnerPadding
        return NSRect(x: inset, y: inset, width: bounds.width - inset * 2, height: sliderHitHeight)
    }

    private var fieldText: String {
        textField?.stringValue ?? ""
    }

    private var expectedText: String {
        VolumeFormatter.percent(model.audio.volume, decimals: model.store.settings.decimals)
    }

    private var isFieldFocused: Bool {
        guard let editor = window.firstResponder as? NSTextView else {
            return false
        }
        return editor.delegate === textField
    }

    private func reset(volume: Double, decimals: Int) async {
        window.makeFirstResponder(nil)
        await settle()
        model.store.settings.decimals = decimals
        model.audio.volume = volume
        await settle()
        model.appliedVolumes = []
    }

    private func focusField() async {
        guard let textField else {
            return
        }
        let center = NSPoint(x: textField.bounds.midX, y: textField.bounds.midY)
        let location = textField.convert(center, to: nil)
        guard let down = mouseEvent(.leftMouseDown, at: location),
              let up = mouseEvent(.leftMouseUp, at: location)
        else {
            return
        }
        NSApp.postEvent(up, atStart: false)
        window.sendEvent(down)
        await settle()
    }

    private func clickSlider(at fraction: CGFloat) async {
        guard let frame = sliderFrame else {
            return
        }
        let location = NSPoint(x: frame.minX + frame.width * fraction, y: frame.midY)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseDragged, .leftMouseUp] {
            guard let event = mouseEvent(type, at: location) else {
                return
            }
            window.sendEvent(event)
            try? await Task.sleep(for: .milliseconds(40))
        }
        await settle()
    }

    private func mouseEvent(_ type: NSEvent.EventType, at location: NSPoint) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: type == .leftMouseDown ? 1 : 0
        )
    }

    private func type(_ text: String) {
        guard let editor = window.firstResponder as? NSTextView else {
            failures.append("입력할 필드 에디터가 없습니다: \(text)")
            return
        }
        editor.selectAll(nil)
        editor.insertText(text, replacementRange: editor.selectedRange())
    }

    private func pressReturn() {
        guard let editor = window.firstResponder as? NSTextView else {
            failures.append("Return 을 보낼 필드 에디터가 없습니다.")
            return
        }
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    }

    private func settle() async {
        try? await Task.sleep(for: .milliseconds(250))
    }

    private func check(_ name: String, _ passed: Bool, _ detail: String = "") {
        print("\(passed ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : "  [\(detail)]")")
        if !passed {
            failures.append(name)
        }
    }

    private func find<T: NSView>(_ type: T.Type, in view: NSView?) -> T? {
        guard let view else {
            return nil
        }
        if let match = view as? T {
            return match
        }
        for subview in view.subviews {
            if let match = find(type, in: subview) {
                return match
            }
        }
        return nil
    }

    private func dumpHierarchy(_ view: NSView?, depth: Int) {
        guard let view else {
            return
        }
        print(String(repeating: "  ", count: depth) + String(describing: Swift.type(of: view)))
        for subview in view.subviews {
            dumpHierarchy(subview, depth: depth + 1)
        }
    }
}

@main
@MainActor
enum VerifyVolumeCard {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let harness = VolumeCardHarness()
        Task { @MainActor in
            let failures = await harness.run()
            print(failures.isEmpty ? "결과: 모두 통과" : "결과: 실패 \(failures.count)건")
            exit(failures.isEmpty ? 0 : 1)
        }
        app.run()
    }
}
