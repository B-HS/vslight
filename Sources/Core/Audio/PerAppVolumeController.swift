import AppKit
import CoreAudio
import Foundation
import Observation

@MainActor
@Observable
final class PerAppVolumeController {
    enum DriverOperation: Equatable {
        case install
        case uninstall
    }

    static let driverUID = "com.bhs.vslight.driver.device"
    static let driverInputUID = "com.bhs.vslight.driver.input"
    static let appVolumesSelector: AudioObjectPropertySelector = 0x6170766C

    let audio: AudioSystem
    let store: SettingsStore
    let loopback = LoopbackEngine()

    private(set) var driverInstalled = false
    /// 진행 중인 드라이버 작업. nil이면 대기 상태다.
    private(set) var driverOperation: DriverOperation?
    /// 현재 드라이버 작업 단계(0...5). 설치·제거 모두 6단계다.
    private(set) var driverStep = 0
    private(set) var lastError: String?
    @ObservationIgnored private var applyTask: Task<Void, Never>?

    var isDriverBusy: Bool {
        driverOperation != nil
    }

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
        driverInstalled = hasDriverDevices()
        if isEnabled, !driverInstalled {
            store.settings.perAppEnabled = false
            restoreOutputStateIfNeeded()
            recoverIfNeeded()
            return
        }
        if isEnabled, !loopback.isRunning, driverInstalled, let monitorDevice {
            do {
                try loopback.start(
                    driverUID: Self.driverUID,
                    driverInputUID: Self.driverInputUID,
                    outputUID: monitorDevice.uid
                )
                applyGains()
            } catch {
                lastError = error.localizedDescription
                store.settings.perAppEnabled = false
                restoreOutputStateIfNeeded()
                recoverIfNeeded()
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
            try loopback.start(
                driverUID: Self.driverUID,
                driverInputUID: Self.driverInputUID,
                outputUID: monitorDevice.uid
            )
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
        guard driverOperation == nil else {
            return
        }
        guard driverSourceURL() != nil else {
            lastError = String(localized: "드라이버 번들이 앱에 없습니다. Scripts/build-driver.sh를 실행하세요.")
            return
        }

        lastError = nil
        driverOperation = .install
        driverStep = 0
        Task { @MainActor [weak self] in
            await self?.performInstall()
        }
    }

    func uninstallDriver() {
        guard driverOperation == nil else {
            return
        }

        lastError = nil
        driverOperation = .uninstall
        driverStep = 0
        Task { @MainActor [weak self] in
            await self?.performUninstall()
        }
    }

    private func performInstall() async {
        defer { finishDriverOperation() }

        driverStep = 0
        await Task.yield()

        driverStep = 1
        if isEnabled {
            setEnabled(false)
        }
        await Task.yield()

        driverStep = 2
        guard let source = driverSourceURL() else {
            lastError = String(localized: "드라이버 번들이 앱에 없습니다. Scripts/build-driver.sh를 실행하세요.")
            return
        }
        let previousDevices = driverDeviceIDs()
        let command = [
            "mkdir -p '/Library/Audio/Plug-Ins/HAL'",
            "rm -rf '/Library/Audio/Plug-Ins/HAL/VSLightAudioDriver.driver'",
            "cp -R '\(escape(source.path))' '/Library/Audio/Plug-Ins/HAL/VSLightAudioDriver.driver'",
            "killall coreaudiod || true"
        ].joined(separator: "; ")

        guard await runPrivileged(command, errorMessage: String(localized: "드라이버 설치에 실패했습니다.")) else {
            return
        }

        driverStep = 3
        try? await Task.sleep(for: .milliseconds(250))

        driverStep = 4
        let installed = await waitForDriverInstalled(previous: previousDevices)
        guard installed else {
            lastError = String(localized: "드라이버가 아직 감지되지 않습니다. coreaudiod를 다시 시작한 뒤 다시 확인하세요.")
            return
        }
        driverInstalled = true
        await Task.yield()

        driverStep = 5
        refresh()
        await Task.yield()
    }

    private func performUninstall() async {
        defer { finishDriverOperation() }

        driverStep = 0
        loopback.stop()
        store.settings.perAppEnabled = false
        await Task.yield()

        driverStep = 1
        restoreOutputStateIfNeeded()
        audio.refresh()
        recoverIfNeeded()
        await Task.yield()

        driverStep = 2
        let userDriver = NSHomeDirectory() + "/Library/Audio/Plug-Ins/HAL/VSLightAudioDriver.driver"
        let command = [
            "rm -rf '/Library/Audio/Plug-Ins/HAL/VSLightAudioDriver.driver'",
            "rm -rf '\(escape(userDriver))'",
            "killall coreaudiod || true"
        ].joined(separator: "; ")

        guard await runPrivileged(command, errorMessage: String(localized: "드라이버 제거에 실패했습니다.")) else {
            return
        }

        driverStep = 3
        try? await Task.sleep(for: .milliseconds(250))

        driverStep = 4
        let removed = await waitForDriverRemoved()
        guard removed else {
            lastError = String(localized: "드라이버가 아직 남아 있습니다. coreaudiod를 다시 시작한 뒤 다시 확인하세요.")
            return
        }
        driverInstalled = false
        await Task.yield()

        driverStep = 5
        clearPerAppSettings()
        lastError = nil
        await Task.yield()
    }

    private func finishDriverOperation() {
        driverOperation = nil
        driverStep = 0
    }

    private func clearPerAppSettings() {
        store.settings.perAppEnabled = false
        store.settings.perAppVolumes = [:]
        store.settings.perAppMuted = [:]
        store.settings.perAppMonitorUID = nil
        store.settings.perAppPreviousOutputVolume = nil
        store.settings.perAppPreviousOutputMuted = nil
    }

    private func driverOutputPresent() -> Bool {
        audio.devices.contains { $0.uid == Self.driverUID }
    }

    private func driverInputPresent() -> Bool {
        AudioDevice.deviceID(forUID: Self.driverInputUID) != nil
    }

    private func hasDriverDevices() -> Bool {
        driverOutputPresent() && driverInputPresent()
    }

    private func driverDeviceIDs() -> (output: AudioObjectID?, input: AudioObjectID?) {
        (
            audio.devices.first { $0.uid == Self.driverUID }?.id,
            AudioDevice.deviceID(forUID: Self.driverInputUID)
        )
    }

    private func waitForDriverInstalled(
        previous: (output: AudioObjectID?, input: AudioObjectID?)
    ) async -> Bool {
        for _ in 0..<18 {
            try? await Task.sleep(for: .milliseconds(100))
            audio.refresh()
            let current = driverDeviceIDs()
            guard let output = current.output, let input = current.input else {
                continue
            }
            if output != previous.output || input != previous.input {
                return true
            }
        }
        audio.refresh()
        return hasDriverDevices()
    }

    private func waitForDriverRemoved() async -> Bool {
        for _ in 0..<18 {
            try? await Task.sleep(for: .milliseconds(100))
            audio.refresh()
            if !driverOutputPresent(), !driverInputPresent(), !driverFilesPresent {
                return true
            }
        }
        audio.refresh()
        return !driverOutputPresent() && !driverInputPresent() && !driverFilesPresent
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

    private func runPrivileged(_ command: String, errorMessage: String) async -> Bool {
        lastError = nil
        let result = await Self.runPrivilegedScript(command)
        guard result.status == 0 else {
            let detail = result.stderr.isEmpty ? "" : " \(result.stderr)"
            lastError = errorMessage + detail
            return false
        }
        return true
    }

    private nonisolated static func runPrivilegedScript(_ command: String) async -> (status: Int32, stderr: String) {
        await Task.detached(priority: .userInitiated) { () -> (status: Int32, stderr: String) in
            let escaped = command
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let script = "do shell script \"" + escaped + "\" with administrator privileges"

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let errorPipe = Pipe()
            process.standardError = errorPipe
            process.standardOutput = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                return (status: 1, stderr: error.localizedDescription)
            }

            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let stderr = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (status: process.terminationStatus, stderr: stderr)
        }.value
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
