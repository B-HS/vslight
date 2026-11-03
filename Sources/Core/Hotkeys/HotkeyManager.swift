import Carbon
import Foundation
import Observation

@MainActor
@Observable
final class HotkeyManager {
    var failures: [UUID: String] = [:]
    var onTrigger: ((UUID) -> Void)?

    private var eventHandler: EventHandlerRef?
    private var registrations: [UInt32: EventHotKeyRef] = [:]
    private var slotToPreset: [UInt32: UUID] = [:]
    private var nextSlot: UInt32 = 1

    func start() {
        guard eventHandler == nil else {
            return
        }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    func stop() {
        unregisterAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        eventHandler = nil
        failures.removeAll()
    }

    func sync(presets: [VolumePreset]) {        unregisterAll()
        failures.removeAll()
        var used: Set<String> = []
        for preset in presets {
            guard let hotkey = preset.hotkey, hotkey.isValid else {
                continue
            }
            let signature = "\(hotkey.keyCode)-\(hotkey.modifiers)"
            guard !used.contains(signature) else {
                failures[preset.id] = "같은 단축키를 다른 프리셋이 사용 중입니다."
                continue
            }
            used.insert(signature)
            let slot = nextSlot
            nextSlot += 1
            let hotKeyID = EventHotKeyID(signature: fourCharCode("VSLT"), id: slot)
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(
                hotkey.keyCode,
                hotkey.modifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &reference
            )
            guard status == noErr, let reference else {
                failures[preset.id] = message(for: status)
                continue
            }
            registrations[slot] = reference
            slotToPreset[slot] = preset.id
        }
    }

    func unregisterAll() {
        for reference in registrations.values {
            UnregisterEventHotKey(reference)
        }
        registrations.removeAll()
        slotToPreset.removeAll()
    }

    fileprivate func handle(slot: UInt32) {
        guard let presetID = slotToPreset[slot] else {
            return
        }
        onTrigger?(presetID)
    }

    private func fourCharCode(_ value: String) -> OSType {
        value.utf8.reduce(0) { partial, byte in
            (partial << 8) + OSType(byte)
        }
    }

    private func message(for status: OSStatus) -> String {
        if status == eventHotKeyExistsErr {
            return "이미 다른 앱이 사용하는 단축키입니다."
        }
        return "단축키를 등록하지 못했습니다. (\(status))"
    }
}

private func hotKeyEventHandler(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else {
        return OSStatus(eventNotHandledErr)
    }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else {
        return status
    }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated {
        manager.handle(slot: hotKeyID.id)
    }
    return noErr
}
