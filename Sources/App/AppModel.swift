import AppKit
import Foundation
import Observation
import ServiceManagement

private final class WeakAppModelBox: @unchecked Sendable {
    weak var model: AppModel?

    init(model: AppModel) {
        self.model = model
    }
}

enum SettingsTab: Hashable {
    case general
    case presets
    case perApp
    case about
}

enum LaunchAtLoginState: Equatable {
    case enabled
    case requiresApproval
    case notRegistered
    case notFound

    init(status: SMAppService.Status) {
        switch status {
        case .enabled:
            self = .enabled
        case .requiresApproval:
            self = .requiresApproval
        case .notFound:
            self = .notFound
        case .notRegistered:
            self = .notRegistered
        @unknown default:
            self = .notRegistered
        }
    }

    var isEnabled: Bool {
        self == .enabled
    }

    var isOn: Bool {
        self == .enabled || self == .requiresApproval
    }

    var label: String {
        switch self {
        case .enabled: String(localized: "로그인 시 자동 실행 켜짐")
        case .requiresApproval: String(localized: "시스템 설정 승인 필요")
        case .notRegistered: String(localized: "로그인 시 자동 실행 꺼짐")
        case .notFound: String(localized: "설치 위치 확인 필요")
        }
    }

    var detail: String? {
        switch self {
        case .enabled: nil
        case .requiresApproval: String(localized: "시스템 설정 > 일반 > 로그인 항목에서 VSLight를 허용하세요.")
        case .notRegistered: nil
        case .notFound: String(localized: "로그인 항목은 /Applications에 설치된 VSLight에서 등록할 수 있습니다.")
        }
    }

    var symbolName: String {
        switch self {
        case .enabled: "checkmark.circle.fill"
        case .requiresApproval: "exclamationmark.triangle.fill"
        case .notRegistered: "circle"
        case .notFound: "xmark.circle.fill"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    let audio: AudioSystem
    let store: SettingsStore
    let hotkeys: HotkeyManager
    let lifecycle: SystemLifecycle
    let perApp: PerAppVolumeController

    var settingsTab: SettingsTab = .general
    var launchAtLoginState: LaunchAtLoginState = .notRegistered
    var lastErrorMessage: String?

    private var hasStarted = false
    private var hasShutdown = false
    private var wakeTask: Task<Void, Never>?
    @ObservationIgnored private var loginRefreshTask: Task<Void, Never>?
    private var terminateObserver: NSObjectProtocol?

    init(
        audio: AudioSystem = AudioSystem(),
        store: SettingsStore = SettingsStore(),
        hotkeys: HotkeyManager = HotkeyManager(),
        lifecycle: SystemLifecycle = SystemLifecycle()
    ) {
        self.audio = audio
        self.store = store
        self.hotkeys = hotkeys
        self.lifecycle = lifecycle
        self.perApp = PerAppVolumeController(audio: audio, store: store)
        hotkeys.onTrigger = { [weak self] presetID in
            self?.applyPreset(id: presetID)
        }
        lifecycle.onWake = { [weak self] in
            self?.handleWake()
        }
        lifecycle.onActivate = { [weak self] in
            self?.handleActivate()
        }
        let box = WeakAppModelBox(model: self)
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                box.model?.shutdown()
            }
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
        perApp.start()
        lifecycle.start()
        applyHotkeys()
        restoreOutputDevice()
        refreshLaunchAtLoginState()
    }

    func shutdown() {
        guard !hasShutdown else {
            return
        }
        hasShutdown = true
        if let terminateObserver {
            NotificationCenter.default.removeObserver(terminateObserver)
        }
        terminateObserver = nil
        wakeTask?.cancel()
        wakeTask = nil
        loginRefreshTask?.cancel()
        loginRefreshTask = nil
        lifecycle.stop()
        hotkeys.stop()
        perApp.stop()
        audio.stop()
        store.flush()
    }

    func setVolume(_ value: Double) {
        audio.setVolume(value)
    }

    func toggleMute() {
        audio.toggleMute()
    }

    func select(_ device: AudioDevice) {
        if perApp.isEnabled, device.uid != PerAppVolumeController.driverUID {
            perApp.setEnabled(false)
        }
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
            refreshLaunchAtLoginState()
            if enabled, launchAtLoginState == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
            lastErrorMessage = nil
            loginRefreshTask?.cancel()
            loginRefreshTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                guard let self, !Task.isCancelled else {
                    return
                }
                self.refreshLaunchAtLoginState()
            }
        } catch {
            refreshLaunchAtLoginState()
            lastErrorMessage = String(localized: "로그인 항목을 변경하지 못했습니다.") + " \(error.localizedDescription)"
        }
    }

    func refreshLaunchAtLoginState() {
        launchAtLoginState = LaunchAtLoginState(status: SMAppService.mainApp.status)
        if launchAtLoginState == .enabled || launchAtLoginState == .notRegistered {
            lastErrorMessage = nil
        }
        let isOn = launchAtLoginState.isOn
        if store.settings.launchAtLogin != isOn {
            store.settings.launchAtLogin = isOn
        }
    }

    func clearError() {
        lastErrorMessage = nil
        audio.clearError()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func restartApp() {
        store.flush()
        hotkeys.stop()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", Bundle.main.bundlePath]
        do {
            try process.run()
        } catch {
            hotkeys.start()
            applyHotkeys()
            lastErrorMessage = String(localized: "앱을 다시 시작하지 못했습니다.") + " \(error.localizedDescription)"
            return
        }
        NSApplication.shared.terminate(nil)
    }

    func openSoundSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func handleWake() {
        refreshLaunchAtLoginState()
        audio.restartMonitoring()
        perApp.refresh()
        applyHotkeys()
        wakeTask?.cancel()
        wakeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else {
                return
            }
            self.audio.scheduleRefresh()
            self.perApp.refresh()
            self.applyHotkeys()
            self.refreshLaunchAtLoginState()
        }
    }

    private func handleActivate() {
        refreshLaunchAtLoginState()
        perApp.refresh()
        if !hotkeys.failures.isEmpty {
            applyHotkeys()
        }
        audio.scheduleRefresh()
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
