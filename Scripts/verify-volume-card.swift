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
private let emptyAreaPoint = NSPoint(x: 4, y: 4)
private let scenarioAttempts = 3

@MainActor
let harnessModel = AppModel()

@MainActor
final class VolumeCardHarness {
    private let model = harnessModel
    private var popover: NSWindow?
    private var lines: [String] = []
    private var scenarioFailures: [String] = []
    private var failures: [String] = []

    func run() async -> [String] {
        await settle()
        await openPopover()
        guard let popover else {
            return ["메뉴 막대 팝오버를 열지 못했습니다. 터미널에 손쉬운 사용 권한이 필요합니다."]
        }
        print("창: \(Swift.type(of: popover)), 열자마자 입력란 포커스: \(isFieldFocused)")

        await scenario("포커스 중 슬라이더", sliderWhileFocused)
        await scenario("포커스 해제 후 슬라이더", sliderKeepsUpdatingAfterRelease)
        await scenario("포커스 중 외부 볼륨 변경", externalChangeWhileFocused)
        await scenario("입력 후 Return", typeAndSubmit)
        await scenario("입력 도중 슬라이더", typeThenSlider)
        await scenario("수정 없이 밖을 클릭", clickOutsideWithoutEdit)
        await scenario("입력 도중 밖을 클릭", typeThenClickOutside)
        await scenario("입력 도중 포커스 이동", typeThenBlur)
        await scenario("수정 없이 포커스 이동", focusThenBlurWithoutEdit)
        return failures
    }

    private func scenario(_ name: String, _ body: () async -> Void) async {
        for _ in 0..<scenarioAttempts {
            if popover?.isVisible != true {
                await openPopover()
            }
            lines = []
            scenarioFailures = []
            await body()
            guard popover?.isVisible == true else {
                continue
            }
            lines.forEach { print($0) }
            failures += scenarioFailures
            return
        }
        print("FAIL  \(name): 검사 도중 팝오버가 닫혔습니다.")
        failures.append(name)
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
        popover?.makeFirstResponder(nil)
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

    private func clickOutsideWithoutEdit() async {
        await reset(volume: 0.5, decimals: 1)
        await focusField()
        check("밖을 클릭하기 전 포커스", isFieldFocused)
        await click(at: emptyAreaPoint)
        check("밖을 클릭하면 포커스 해제", !isFieldFocused)
        check("밖을 클릭해도 볼륨을 바꾸지 않음", model.appliedVolumes.isEmpty && fieldText == "50.0", "applied=\(model.appliedVolumes) field=\(fieldText)")
        await clickSlider(at: 0.7)
        check("밖을 클릭한 뒤 슬라이더 변경이 숫자에 반영됨", fieldText == expectedText && fieldText != "50.0", "field=\(fieldText) expected=\(expectedText)")
    }

    private func typeThenClickOutside() async {
        await reset(volume: 0.5, decimals: 1)
        await focusField()
        type("30")
        await settle()
        await click(at: emptyAreaPoint)
        check("입력 도중 밖을 클릭하면 포커스 해제", !isFieldFocused)
        check("입력 도중 밖을 클릭하면 현재 볼륨으로 되돌아감", model.appliedVolumes.isEmpty && fieldText == "50.0", "applied=\(model.appliedVolumes) field=\(fieldText)")
    }

    private func typeThenBlur() async {
        await reset(volume: 0.5, decimals: 1)
        await focusField()
        type("30")
        await settle()
        popover?.makeFirstResponder(nil)
        await settle()
        check("입력 도중 포커스를 잃으면 현재 볼륨으로 되돌아감", model.appliedVolumes.isEmpty && fieldText == "50.0", "applied=\(model.appliedVolumes) field=\(fieldText)")
    }

    private func focusThenBlurWithoutEdit() async {
        await reset(volume: 0.637, decimals: 0)
        await focusField()
        popover?.makeFirstResponder(nil)
        await settle()
        check("수정 없이 포커스를 잃으면 볼륨을 바꾸지 않음", model.appliedVolumes.isEmpty, "applied=\(model.appliedVolumes)")
    }

    private var textField: NSTextField? {
        find(NSTextField.self, in: popover?.contentView)
    }

    private var sliderFrame: NSRect? {
        guard let bounds = popover?.contentView?.bounds else {
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
        guard let editor = popover?.firstResponder as? NSTextView else {
            return false
        }
        return editor.delegate === textField
    }

    private func openPopover() async {
        let button = NSApp.windows.lazy.compactMap { self.find(NSStatusBarButton.self, in: $0.contentView) }.first
        guard let frame = button?.window?.frame, let screenHeight = NSScreen.screens.first?.frame.height else {
            return
        }
        let point = CGPoint(x: frame.midX, y: screenHeight - frame.midY)
        let cursor = CGEvent(source: nil)?.location
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            try? await Task.sleep(for: .milliseconds(60))
        }
        await settle()
        if let cursor {
            CGWarpMouseCursorPosition(cursor)
        }
        await settle()
        popover = NSApp.windows.first { $0.isVisible && self.find(NSTextField.self, in: $0.contentView) != nil }
    }

    private func reset(volume: Double, decimals: Int) async {
        popover?.makeFirstResponder(nil)
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
        NSApp.sendEvent(down)
        await settle()
    }

    private func clickSlider(at fraction: CGFloat) async {
        guard let frame = sliderFrame else {
            return
        }
        await click(at: NSPoint(x: frame.minX + frame.width * fraction, y: frame.midY))
    }

    private func click(at location: NSPoint) async {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseDragged, .leftMouseUp] {
            guard let event = mouseEvent(type, at: location) else {
                return
            }
            NSApp.sendEvent(event)
            try? await Task.sleep(for: .milliseconds(40))
        }
        await settle()
    }

    private func mouseEvent(_ type: NSEvent.EventType, at location: NSPoint) -> NSEvent? {
        guard let popover else {
            return nil
        }
        return NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: popover.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: type == .leftMouseDown ? 1 : 0
        )
    }

    private func type(_ text: String) {
        guard let editor = popover?.firstResponder as? NSTextView else {
            check("입력할 필드 에디터 있음", false, text)
            return
        }
        editor.selectAll(nil)
        editor.insertText(text, replacementRange: editor.selectedRange())
    }

    private func pressReturn() {
        guard let editor = popover?.firstResponder as? NSTextView else {
            check("Return 을 보낼 필드 에디터 있음", false)
            return
        }
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    }

    private func settle() async {
        try? await Task.sleep(for: .milliseconds(250))
    }

    private func check(_ name: String, _ passed: Bool, _ detail: String = "") {
        lines.append("\(passed ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : "  [\(detail)]")")
        if !passed {
            scenarioFailures.append(name)
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
}

@MainActor
final class HarnessDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        setvbuf(stdout, nil, _IONBF, 0)
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            let failures = await VolumeCardHarness().run()
            print(failures.isEmpty ? "결과: 모두 통과" : "결과: 실패 \(failures.count)건")
            exit(failures.isEmpty ? 0 : 1)
        }
    }
}

@main
struct VerifyVolumeCard: App {
    @NSApplicationDelegateAdaptor(HarnessDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            VolumeCardView()
                .environment(harnessModel)
                .padding(cardOuterPadding)
                .frame(width: 304)
        } label: {
            Image(systemName: "checkmark.circle")
        }
        .menuBarExtraStyle(.window)
    }
}
