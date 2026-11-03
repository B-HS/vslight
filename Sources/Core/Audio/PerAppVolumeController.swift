import AppKit
import CoreAudio
import Foundation
import Observation

@MainActor
@Observable
final class PerAppVolumeController {
    static let driverUID = "com.bhs.vslight.driver.device"
    static let appVolumesSelector: AudioObjectPropertySelector = 0x6170766C

    let audio: AudioSystem
    let store: SettingsStore
    let loopback = LoopbackEngine()

    private(set) var driverInstalled = false
    private(set) var isDriverBusy = false
    private(set) var lastError: String?
    @ObservationIgnored private var applyTask: Task<Void, Never>?

    var driverFilesPresent: Bool {
        let system = "/Library/Audio/Plug-Ins/HAL/VSLightAudioDriver.driver"
        let user = NSHomeDirectory() + "/Library/Audio/Plug-Ins/HAL/VSLightAudioDriver.driver"
        return FileManager.default.fileExists(atPath: system) || FileManager.default.fileExists(atPath: user)
    }

    init(audio: AudioSystem, store: SettingsStore) {
        self.audio = audio
        self.store = store
    }

    var isEnabled: Bool {
        store.settings.perAppEnabled
    }

    var realOutputDevices: [AudioDevice] {
        audio.devices.filter { $0.uid != Self.driverUID }
    }

    var monitorDevice: AudioDevice? {
        if let uid = store.settings.perAppMonitorUID,
           let device = realOutputDevices.first(where: { $0.uid == uid }) {
            return device
        }
        if let defaultID = AudioDevice.defaultOutputID(),
           let device = realOutputDevices.first(where: { $0.id == defaultID }) {
            return device
        }
        return realOutputDevices.first
    }

    func start() {
        refresh()
    }

    func stop() {
        applyTask?.cancel()
        applyTask = nil
        loopback.stop()
    }

    func refresh() {
        audio.refreshProcesses()
        driverInstalled = audio.devices.contains { $0.uid == Self.driverUID }
        if isEnabled, !driverInstalled {
            store.settings.perAppEnabled = false
            restoreOutputStateIfNeeded()
            recoverIfNeeded()
            return
        }
        if isEnabled, !loopback.isRunning, driverInstalled, let monitorDevice {
            do {
                try loopback.start(driverUID: Self.driverUID, outputUID: monitorDevice.uid)
                applyGains()
            } catch {
                lastError = error.localizedDescription
            }
        }
        if !isEnabled {
            restoreOutputStateIfNeeded()
        }
        recoverIfNeeded()
    }

    func setEnabled(_ enabled: Bool) {
        lastError = nil
        if !enabled {
            loopback.stop()
            store.settings.perAppEnabled = false
            restoreOutputStateIfNeeded()
            audio.refresh()
            recoverIfNeeded()
            return
        }

        guard driverInstalled else {
            lastError = String(localized: "앱별 볼륨을 사용하려면 드라이버를 설치하세요.")
            return
        }
        guard let monitorDevice else {
            lastError = LoopbackError.outputMissing.localizedDescription
            return
        }

        saveOutputState(for: monitorDevice)
        do {
            try loopback.start(driverUID: Self.driverUID, outputUID: monitorDevice.uid)
            store.settings.perAppEnabled = true
            applyGains()
        } catch {
            lastError = error.localizedDescription
            store.settings.perAppEnabled = false
            restoreOutputStateIfNeeded()
        }
    }

    func setMonitor(_ device: AudioDevice) {
        let wasEnabled = isEnabled
        if wasEnabled {
            setEnabled(false)
        }
        store.settings.perAppMonitorUID = device.uid
        if wasEnabled {
            setEnabled(true)
        }
    }

    func volume(for process: AudioProcess) -> Double {
        store.settings.perAppVolumes[key(for: process)] ?? 1.0
    }

    func setVolume(_ value: Double, for process: AudioProcess) {
        let clamped = min(max(value, 0), 1)
        let key = key(for: process)
        if clamped >= 0.9995 {
            store.settings.perAppVolumes.removeValue(forKey: key)
        } else {
            store.settings.perAppVolumes[key] = clamped
        }
        scheduleApply()
    }

    func isMuted(_ process: AudioProcess) -> Bool {
        store.settings.perAppMuted[key(for: process)] ?? false
    }

    func toggleMute(_ process: AudioProcess) {
        let key = key(for: process)
        if isMuted(process) {
            store.settings.perAppMuted.removeValue(forKey: key)
        } else {
            store.settings.perAppMuted[key] = true
        }
        scheduleApply()
    }

    func applyGains() {
        guard let driver = audio.devices.first(where: { $0.uid == Self.driverUID }) else {
            return
        }

        var entries: [[String: Any]] = []
        for process in audio.processes {
            let key = key(for: process)
            let volume = store.settings.perAppVolumes[key] ?? 1.0
            let muted = store.settings.perAppMuted[key] ?? false
            guard volume < 0.9995 || muted else {
                continue
            }
            var entry: [String: Any] = [
                "volume": volume,
                "muted": muted
            ]
            if let bundleID = process.bundleID, !bundleID.isEmpty {
                entry["bundleID"] = bundleID
            } else {
                entry["pid"] = process.pid
            }
            entries.append(entry)
        }

        var address = audioPropertyAddress(Self.appVolumesSelector)
        var value = entries as CFArray
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectSetPropertyData(
                driver.id,
                &address,
                0,
                nil,
                UInt32(MemoryLayout<CFArray>.size),
                pointer
            )
        }
        if status != noErr {
            lastError = String(localized: "앱별 볼륨을 적용하지 못했습니다.") + " (\(status))"
        }
    }

    func scheduleApply() {
        applyTask?.cancel()
        applyTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard let self, !Task.isCancelled else {
                return
            }
            self.applyGains()
        }
    }

    func installDriver() {
        guard !isDriverBusy else {
            return
        }
        guard let source = driverSourceURL() else {
            lastError = String(localized: "드라이버 번들이 앱에 없습니다. Scripts/build-driver.sh를 실행하세요.")
            return
        }

        isDriverBusy = true
        lastError = nil
        let command = [
            "mkdir -p '/Library/Audio/Plug-Ins/HAL'",
            "rm -rf '/Library/Audio/Plug-Ins/HAL/VSLightAudioDriver.driver'",
            "cp -R '\(escape(source.path))' '/Library/Audio/Plug-Ins/HAL/VSLightAudioDriver.driver'",
            "killall coreaudiod || true"
        ].joined(separator: "; ")

        guard runPrivileged(command, errorMessage: String(localized: "드라이버 설치에 실패했습니다.")) else {
            isDriverBusy = false
            return
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard let self else {
                return
            }
            self.audio.refresh()
            self.driverInstalled = self.audio.devices.contains { $0.uid == Self.driverUID }
            if !self.driverInstalled {
                self.lastError = String(localized: "드라이버가 아직 감지되지 않습니다. coreaudiod를 다시 시작한 뒤 다시 확인하세요.")
            }
            self.isDriverBusy = false
        }
    }

    func uninstallDriver() {
        guard !isDriverBusy else {
            return
        }

        setEnabled(false)
        recoverIfNeeded()
        isDriverBusy = true
        lastError = nil

        let userDriver = NSHomeDirectory() + "/Library/Audio/Plug-Ins/HAL/VSLightAudioDriver.driver"
        let command = [
            "rm -rf '/Library/Audio/Plug-Ins/HAL/VSLightAudioDriver.driver'",
            "rm -rf '\(escape(userDriver))'",
            "killall coreaudiod || true"
        ].joined(separator: "; ")

        guard runPrivileged(command, errorMessage: String(localized: "드라이버 제거에 실패했습니다.")) else {
            isDriverBusy = false
            return
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1800))
            guard let self else {
                return
            }
            self.audio.refresh()
            self.driverInstalled = self.audio.devices.contains { $0.uid == Self.driverUID }
            if self.driverInstalled || self.driverFilesPresent {
                self.lastError = String(localized: "드라이버가 아직 남아 있습니다. coreaudiod를 다시 시작한 뒤 다시 확인하세요.")
            } else {
                self.clearPerAppSettings()
                self.lastError = nil
            }
            self.isDriverBusy = false
        }
    }

    private func clearPerAppSettings() {
        store.settings.perAppEnabled = false
        store.settings.perAppVolumes = [:]
        store.settings.perAppMuted = [:]
        store.settings.perAppMonitorUID = nil
        store.settings.perAppPreviousOutputVolume = nil
        store.settings.perAppPreviousOutputMuted = nil
    }

    private func driverSourceURL() -> URL? {
        guard let resourceURL = Bundle.main.resourceURL else {
            return nil
        }
        let source = resourceURL.appending(path: "VSLightAudioDriver.driver")
        return FileManager.default.fileExists(atPath: source.path) ? source : nil
    }

    func clearError() {
        lastError = nil
    }

    private func key(for process: AudioProcess) -> String {
        if let bundleID = process.bundleID, !bundleID.isEmpty {
            return bundleID
        }
        return "pid:\(process.pid)"
    }

    private var outputVolumeAddress: AudioObjectPropertyAddress {
        audioPropertyAddress(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput)
    }

    private var outputMuteAddress: AudioObjectPropertyAddress {
        audioPropertyAddress(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
    }

    private func readVolume(_ device: AudioDevice) -> Float? {
        try? AudioProperty.get(device.id, outputVolumeAddress, defaultValue: Float(0))
    }

    private func readMute(_ device: AudioDevice) -> Bool? {
        guard let value: UInt32 = try? AudioProperty.get(device.id, outputMuteAddress, defaultValue: 0) else {
            return nil
        }
        return value != 0
    }

    private func setVolume(_ device: AudioDevice, _ value: Float) {
        try? AudioProperty.set(
            device.id,
            outputVolumeAddress,
            value: min(max(value, 0), 1)
        )
    }

    private func setMute(_ device: AudioDevice, _ muted: Bool) {
        try? AudioProperty.set(
            device.id,
            outputMuteAddress,
            value: UInt32(muted ? 1 : 0)
        )
    }

    private func saveOutputState(for device: AudioDevice) {
        store.settings.perAppPreviousOutputVolume = readVolume(device).map(Double.init)
        store.settings.perAppPreviousOutputMuted = readMute(device)
    }

    private func restoreOutputStateIfNeeded() {
        guard !isEnabled, let monitorDevice else {
            return
        }

        if let volume = store.settings.perAppPreviousOutputVolume {
            setVolume(monitorDevice, Float(volume))
        }
        if let muted = store.settings.perAppPreviousOutputMuted {
            setMute(monitorDevice, muted)
        }

        store.settings.perAppPreviousOutputVolume = nil
        store.settings.perAppPreviousOutputMuted = nil
    }

    private func runPrivileged(_ command: String, errorMessage: String) -> Bool {
        lastError = nil
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"" + escaped + "\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error {
            let detail = error[NSAppleScript.errorMessage] as? String ?? ""
            lastError = "\(errorMessage) \(detail)"
            return false
        }
        return true
    }

    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\\''")
    }

    private func recoverIfNeeded() {
        guard !isEnabled else {
            return
        }
        guard let monitorDevice,
              let defaultID = AudioDevice.defaultOutputID()
        else {
            return
        }
        let devices = AudioDevice.allOutputDevices()
        guard devices.first(where: { $0.id == defaultID })?.uid == Self.driverUID else {
            return
        }
        let value = monitorDevice.id
        try? AudioProperty.set(
            systemAudioObject,
            audioPropertyAddress(kAudioHardwarePropertyDefaultOutputDevice),
            value: value
        )
    }
}
