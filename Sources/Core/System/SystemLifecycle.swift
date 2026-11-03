import AppKit
import Foundation

@MainActor
final class SystemLifecycle {
    var onWake: (@MainActor () -> Void)?
    var onActivate: (@MainActor () -> Void)?

    private var tasks: [Task<Void, Never>] = []
    private var isStarted = false

    func start() {
        guard !isStarted else {
            return
        }
        isStarted = true
        let workspaceCenter = NSWorkspace.shared.notificationCenter

        tasks.append(Task { @MainActor [weak self] in
            for await _ in workspaceCenter.notifications(named: NSWorkspace.didWakeNotification) {
                guard let self else {
                    return
                }
                self.onWake?()
            }
        })

        tasks.append(Task { @MainActor [weak self] in
            for await _ in workspaceCenter.notifications(named: NSWorkspace.screensDidWakeNotification) {
                guard let self else {
                    return
                }
                self.onWake?()
            }
        })

        tasks.append(Task { @MainActor [weak self] in
            for await _ in workspaceCenter.notifications(named: NSWorkspace.sessionDidBecomeActiveNotification) {
                guard let self else {
                    return
                }
                self.onActivate?()
            }
        })

        tasks.append(Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                guard let self else {
                    return
                }
                self.onActivate?()
            }
        })
    }

    func stop() {
        for task in tasks {
            task.cancel()
        }
        tasks.removeAll()
        isStarted = false
    }
}
