import AppKit
import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class AppModel {
    let audio: AudioSystem
    let store: SettingsStore
    let hotkeys: HotkeyManager
    var lastErrorMessage: String?
    private var hasStarted = false

    init(
        audio: AudioSystem = AudioSystem(),
        store: SettingsStore = SettingsStore(),
        hotkeys: HotkeyManager = HotkeyManager()
    ) {
        self.audio = audio
        self.store = store
        self.hotkeys = hotkeys
        hotkeys.onTrigger = { [weak self] presetID in
            self?.applyPreset(id: presetID)
        }
        Task { @MainActor [weak self] in
            self?.start()
        }
    }

    func start() {
        guard !hasStarted else {
            return
        }
        hasStarted = true
        hotkeys.start()
        audio.start()
        applyHotkeys()
        restoreOutputDevice()
    }

    var versionText: String {
        AppVersion.short
    }

    var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setVolume(_ value: Double) {
        audio.setVolume(value)
    }

    func toggleMute() {
        audio.toggleMute()
    }

    func select(_ device: AudioDevice) {
        audio.select(device)
        store.settings.lastOutputDeviceUID = device.uid
    }

    func applyPreset(id: UUID) {
        guard let preset = store.settings.presets.first(where: { $0.id == id }) else {
            return
        }
        apply(preset)
    }

    func apply(_ preset: VolumePreset) {
        if let uid = preset.deviceUID,
           let device = audio.devices.first(where: { $0.uid == uid }) {
            audio.select(device)
            store.settings.lastOutputDeviceUID = device.uid
        }
        audio.setVolume(preset.volume)
    }

    func applyHotkeys() {
        hotkeys.sync(presets: store.settings.hotkeysEnabled ? store.settings.presets : [])
    }

    func hotkeyFailure(for preset: VolumePreset) -> String? {
        hotkeys.failures[preset.id]
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            store.settings.launchAtLogin = enabled
        } catch {
            store.settings.launchAtLogin = isLaunchAtLoginEnabled
            lastErrorMessage = "로그인 항목을 변경하지 못했습니다. \(error.localizedDescription)"
        }
    }

    func openSoundSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func restoreOutputDevice() {
        guard store.settings.restoreLastOutputDevice,
              let uid = store.settings.lastOutputDeviceUID,
              let device = audio.devices.first(where: { $0.uid == uid })
        else {
            return
        }
        audio.select(device)
    }
}

enum AppVersion {
    static var short: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
}
