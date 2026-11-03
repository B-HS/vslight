import AppKit
import CoreAudio
import Foundation
import Observation

@MainActor
@Observable
final class AudioSystem {
    private(set) var devices: [AudioDevice] = []
    private(set) var defaultDeviceID: AudioObjectID = kAudioObjectUnknown
    private(set) var volume: Double = 0
    private(set) var isMuted = false
    private(set) var canSetVolume = false
    private(set) var canSetMute = false
    private(set) var processes: [AudioProcess] = []
    private(set) var lastError: String?

    private var globalListeners: [ListenerToken] = []
    private var volumeListeners: [ListenerToken] = []
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var restartTask: Task<Void, Never>?
    private var isStarted = false

    private struct ListenerToken {
        let object: AudioObjectID
        let address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
        let queue: DispatchQueue
    }

    var currentDevice: AudioDevice? {
        devices.first { $0.id == defaultDeviceID }
    }

    var deviceName: String {
        currentDevice?.name ?? "출력 장치 없음"
    }

    var menuBarSymbol: String {
        if isMuted || volume <= 0.0001 {
            return "speaker.slash.fill"
        }
        return "speaker.wave.3.fill"
    }

    var volumeText: String {
        VolumeFormatter.percent(volume, decimals: 1)
    }

    func start() {
        guard !isStarted else {
            return
        }
        isStarted = true
        installGlobalListeners()
        refresh()
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        restartTask?.cancel()
        restartTask = nil
        remove(globalListeners)
        globalListeners.removeAll()
        remove(volumeListeners)
        volumeListeners.removeAll()
        isStarted = false
    }

    func restartMonitoring() {
        guard isStarted else {
            return
        }
        refreshTask?.cancel()
        refreshTask = nil
        restartTask?.cancel()
        restartTask = nil
        remove(globalListeners)
        globalListeners.removeAll()
        remove(volumeListeners)
        volumeListeners.removeAll()
        installGlobalListeners()
        refresh()
    }

    func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self, !Task.isCancelled else {
                return
            }
            self.refresh()
        }
    }

    func refresh() {
        devices = AudioDevice.allOutputDevices()
        defaultDeviceID = AudioDevice.defaultOutputID() ?? kAudioObjectUnknown
        refreshProcesses()
        refreshVolumeListeners()
        readVolumeState()
    }

    func select(_ device: AudioDevice) {
        do {
            try AudioProperty.set(
                systemAudioObject,
                audioPropertyAddress(kAudioHardwarePropertyDefaultOutputDevice),
                value: device.id
            )
            defaultDeviceID = device.id
            lastError = nil
            refreshVolumeListeners()
            readVolumeState()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func clearError() {
        lastError = nil
    }

    func setVolume(_ newValue: Double) {
        let clamped = min(max(newValue, 0), 1)
        volume = clamped
        guard defaultDeviceID != kAudioObjectUnknown else {
            return
        }
        let address = mainVolumeAddress
        do {
            if AudioProperty.isSettable(defaultDeviceID, address) {
                try AudioProperty.set(defaultDeviceID, address, value: Float(clamped))
            } else {
                try setChannelVolume(Float(clamped))
            }
            canSetVolume = true
            lastError = nil
            if clamped > 0, isMuted {
                try? setMute(false)
                isMuted = false
            }
        } catch {
            lastError = error.localizedDescription
            canSetVolume = false
        }
    }

    func toggleMute() {
        setMuted(!isMuted)
    }

    func setMuted(_ muted: Bool) {
        guard defaultDeviceID != kAudioObjectUnknown else {
            return
        }
        do {
            try setMute(muted)
            isMuted = muted
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private var mainVolumeAddress: AudioObjectPropertyAddress {
        audioPropertyAddress(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput)
    }

    private var mainMuteAddress: AudioObjectPropertyAddress {
        audioPropertyAddress(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
    }

    private func readVolumeState() {
        guard defaultDeviceID != kAudioObjectUnknown else {
            volume = 0
            isMuted = false
            canSetVolume = false
            canSetMute = false
            return
        }
        let mainVolume = mainVolumeAddress
        if let value: Float = try? AudioProperty.get(defaultDeviceID, mainVolume, defaultValue: 0) {
            volume = Double(value)
            canSetVolume = AudioProperty.isSettable(defaultDeviceID, mainVolume)
                || hasSettableChannel(kAudioDevicePropertyVolumeScalar)
        } else if let value = readChannelVolume() {
            volume = Double(value)
            canSetVolume = hasSettableChannel(kAudioDevicePropertyVolumeScalar)
        } else {
            canSetVolume = false
        }
        let muteAddress = mainMuteAddress
        if let value: UInt32 = try? AudioProperty.get(defaultDeviceID, muteAddress, defaultValue: 0) {
            isMuted = value != 0
            canSetMute = AudioProperty.isSettable(defaultDeviceID, muteAddress)
                || hasSettableChannel(kAudioDevicePropertyMute)
        } else {
            isMuted = false
            canSetMute = false
        }
    }

    private func hasSettableChannel(_ selector: AudioObjectPropertySelector) -> Bool {
        let channels = currentDevice?.outputChannels ?? 0
        guard channels > 0 else {
            return false
        }
        for channel in 1...channels {
            let address = audioPropertyAddress(
                selector,
                scope: kAudioDevicePropertyScopeOutput,
                element: AudioObjectPropertyElement(channel)
            )
            if AudioProperty.isSettable(defaultDeviceID, address) {
                return true
            }
        }
        return false
    }

    private func readChannelVolume() -> Float? {
        let channels = currentDevice?.outputChannels ?? 0
        guard channels > 0 else {
            return nil
        }
        var total: Float = 0
        var found = 0
        for channel in 1...channels {
            let address = audioPropertyAddress(
                kAudioDevicePropertyVolumeScalar,
                scope: kAudioDevicePropertyScopeOutput,
                element: AudioObjectPropertyElement(channel)
            )
            if let value: Float = try? AudioProperty.get(defaultDeviceID, address, defaultValue: 0) {
                total += value
                found += 1
            }
        }
        guard found > 0 else {
            return nil
        }
        return total / Float(found)
    }

    private func setChannelVolume(_ value: Float) throws {
        let channels = currentDevice?.outputChannels ?? 0
        guard channels > 0 else {
            throw AudioPropertyError.missingValue
        }
        var applied = false
        for channel in 1...channels {
            let address = audioPropertyAddress(
                kAudioDevicePropertyVolumeScalar,
                scope: kAudioDevicePropertyScopeOutput,
                element: AudioObjectPropertyElement(channel)
            )
            if AudioProperty.isSettable(defaultDeviceID, address) {
                try AudioProperty.set(defaultDeviceID, address, value: value)
                applied = true
            }
        }
        guard applied else {
            throw AudioPropertyError.missingValue
        }
    }

    private func setMute(_ muted: Bool) throws {
        let address = mainMuteAddress
        if AudioProperty.isSettable(defaultDeviceID, address) {
            try AudioProperty.set(defaultDeviceID, address, value: UInt32(muted ? 1 : 0))
            canSetMute = true
            return
        }
        let channels = currentDevice?.outputChannels ?? 0
        guard channels > 0 else {
            throw AudioPropertyError.missingValue
        }
        var applied = false
        for channel in 1...channels {
            let channelAddress = audioPropertyAddress(
                kAudioDevicePropertyMute,
                scope: kAudioDevicePropertyScopeOutput,
                element: AudioObjectPropertyElement(channel)
            )
            if AudioProperty.isSettable(defaultDeviceID, channelAddress) {
                try AudioProperty.set(defaultDeviceID, channelAddress, value: UInt32(muted ? 1 : 0))
                applied = true
            }
        }
        guard applied else {
            throw AudioPropertyError.missingValue
        }
        canSetMute = true
    }

    private func installGlobalListeners() {
        install(
            object: systemAudioObject,
            address: audioPropertyAddress(kAudioHardwarePropertyDefaultOutputDevice),
            into: &globalListeners
        ) { [weak self] in
            self?.scheduleRefresh()
        }
        install(
            object: systemAudioObject,
            address: audioPropertyAddress(kAudioHardwarePropertyDevices),
            into: &globalListeners
        ) { [weak self] in
            self?.scheduleRefresh()
        }
        install(
            object: systemAudioObject,
            address: audioPropertyAddress(kAudioHardwarePropertyProcessObjectList),
            into: &globalListeners
        ) { [weak self] in
            self?.refreshProcesses()
        }
        install(
            object: systemAudioObject,
            address: audioPropertyAddress(kAudioHardwarePropertyServiceRestarted),
            into: &globalListeners
        ) { [weak self] in
            self?.handleServiceRestart()
        }
    }

    private func handleServiceRestart() {
        restartTask?.cancel()
        restartTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, !Task.isCancelled else {
                return
            }
            self.restartMonitoring()
        }
    }

    private func refreshVolumeListeners() {
        remove(volumeListeners)
        volumeListeners.removeAll()
        guard defaultDeviceID != kAudioObjectUnknown else {
            return
        }
        if AudioProperty.has(defaultDeviceID, mainVolumeAddress) {
            install(object: defaultDeviceID, address: mainVolumeAddress, into: &volumeListeners) { [weak self] in
                self?.readVolumeState()
            }
        }
        if AudioProperty.has(defaultDeviceID, mainMuteAddress) {
            install(object: defaultDeviceID, address: mainMuteAddress, into: &volumeListeners) { [weak self] in
                self?.readVolumeState()
            }
        }
        installChannelListeners(kAudioDevicePropertyVolumeScalar)
        installChannelListeners(kAudioDevicePropertyMute)
    }

    private func installChannelListeners(_ selector: AudioObjectPropertySelector) {
        let channels = currentDevice?.outputChannels ?? 0
        guard channels > 0 else {
            return
        }
        for channel in 1...channels {
            let address = audioPropertyAddress(
                selector,
                scope: kAudioDevicePropertyScopeOutput,
                element: AudioObjectPropertyElement(channel)
            )
            guard AudioProperty.has(defaultDeviceID, address) else {
                continue
            }
            install(object: defaultDeviceID, address: address, into: &volumeListeners) { [weak self] in
                self?.readVolumeState()
            }
        }
    }

    private func install(
        object: AudioObjectID,
        address: AudioObjectPropertyAddress,
        into tokens: inout [ListenerToken],
        handler: @escaping @MainActor () -> Void
    ) {
        var address = address
        let queue = DispatchQueue.main
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            MainActor.assumeIsolated {
                handler()
            }
        }
        let status = AudioObjectAddPropertyListenerBlock(object, &address, queue, block)
        guard status == noErr else {
            return
        }
        tokens.append(ListenerToken(object: object, address: address, block: block, queue: queue))
    }

    private func remove(_ tokens: [ListenerToken]) {
        for token in tokens {
            var address = token.address
            AudioObjectRemovePropertyListenerBlock(token.object, &address, token.queue, token.block)
        }
    }

    func refreshProcesses() {
        let address = audioPropertyAddress(kAudioHardwarePropertyProcessObjectList)
        guard let ids = try? AudioProperty.getArray(systemAudioObject, address) else {
            processes = []
            return
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        processes = ids.compactMap { objectID in
            guard let pid: pid_t = try? AudioProperty.get(objectID, audioPropertyAddress(kAudioProcessPropertyPID), defaultValue: 0),
                  pid > 0,
                  pid != ownPID
            else {
                return nil
            }
            let isRunningOutput: UInt32 = (try? AudioProperty.get(objectID, audioPropertyAddress(kAudioProcessPropertyIsRunningOutput), defaultValue: 0)) ?? 0
            guard isRunningOutput != 0 else {
                return nil
            }
            let bundleID = try? AudioProperty.getString(objectID, audioPropertyAddress(kAudioProcessPropertyBundleID))
            let app = NSRunningApplication(processIdentifier: pid)
            let name = app?.localizedName ?? bundleID ?? "알 수 없는 앱"
            return AudioProcess(id: objectID, pid: pid, bundleID: bundleID, name: name)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
