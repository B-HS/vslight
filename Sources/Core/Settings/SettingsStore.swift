import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class SettingsStore {
    var settings: AppSettings {
        didSet {
            scheduleSave()
        }
    }

    private let fileURL: URL
    private let logger = Logger(subsystem: "com.bhs.vslight", category: "settings")
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(fileURL: URL = SettingsStore.defaultFileURL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
        }
    }

    static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        return base.appending(path: "VSLight/settings.json")
    }

    func flush() {
        saveTask?.cancel()
        saveTask = nil
        saveNow()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else {
                return
            }
            self.saveNow()
        }
    }

    private func saveNow() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(settings)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("설정 저장 실패: \(error.localizedDescription, privacy: .public)")
        }
    }
}
