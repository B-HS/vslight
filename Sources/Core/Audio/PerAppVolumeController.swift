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
    private(set) var lastError: String?
    @ObservationIgnored private var applyTask: Task<Void, Never>?

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
        recoverIfNeeded()
    }

    func setEnabled(_ enabled: Bool) {
        lastError = nil
        if !enabled {
            loopback.stop()
            store.settings.perAppEnabled = false
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

        do {
            try loopback.start(driverUID: Self.driverUID, outputUID: monitorDevice.uid)
            store.settings.perAppEnabled = true
            applyGains()
        } catch {
            lastError = error.localizedDescription
            store.settings.perAppEnabled = false
        }
    }

    func setMonitor(_ device: AudioDevice) {
        store.settings.perAppMonitorUID = device.uid
        guard isEnabled else {
            return
        }
        loopback.stop()
        do {
            try loopback.start(driverUID: Self.driverUID, outputUID: device.uid)
            applyGains()
        } catch {
            lastError = error.localizedDescription
            store.settings.perAppEnabled = false
            recoverIfNeeded()
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
        guard let resourceURL = Bundle.main.resourceURL else {
            lastError = String(localized: "드라이버 번들이 앱에 없습니다. Scripts/build-driver.sh를 실행하세요.")
            return
        }
        let source = resourceURL.appending(path: "VSLightAudioDriver.driver")
        guard FileManager.default.fileExists(atPath: source.path) else {
            lastError = String(localized: "드라이버 번들이 앱에 없습니다. Scripts/build-driver.sh를 실행하세요.")
            return
        }

        let command = [
            "mkdir -p '/Library/Audio/Plug-Ins/HAL'",
            "rm -rf '/Library/Audio/Plug-Ins/HAL/VSLightAudioDriver.driver'",
            "cp -R '\(escape(source.path))' '/Library/Audio/Plug-Ins/HAL/VSLightAudioDriver.driver'",
            "killall coreaudiod || true"
        ].joined(separator: "; ")
        runPrivileged(command, errorMessage: String(localized: "드라이버 설치에 실패했습니다."))
    }

    func uninstallDriver() {
        let command = [
            "rm -rf '/Library/Audio/Plug-Ins/HAL/VSLightAudioDriver.driver'",
            "killall coreaudiod || true"
        ].joined(separator: "; ")
        runPrivileged(command, errorMessage: String(localized: "드라이버 제거에 실패했습니다."))
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

    private func runPrivileged(_ command: String, errorMessage: String) {
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
            return
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard let self else {
                return
            }
            self.audio.refresh()
            self.refresh()
        }
    }

    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\\''")
    }

    private func recoverIfNeeded() {
        guard !isEnabled else {
            return
        }
        guard let defaultID = AudioDevice.defaultOutputID(),
              audio.devices.first(where: { $0.id == defaultID })?.uid == Self.driverUID,
              let monitorDevice
        else {
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
