import Foundation

struct AppSettings: Codable, Hashable, Sendable {
    var presets: [VolumePreset]
    var decimals: Int
    var showPercentageInMenuBar: Bool
    var launchAtLogin: Bool
    var restoreLastOutputDevice: Bool
    var lastOutputDeviceUID: String?
    var hotkeysEnabled: Bool

    init(
        presets: [VolumePreset] = [],
        decimals: Int = 1,
        showPercentageInMenuBar: Bool = false,
        launchAtLogin: Bool = false,
        restoreLastOutputDevice: Bool = false,
        lastOutputDeviceUID: String? = nil,
        hotkeysEnabled: Bool = true
    ) {
        self.presets = presets
        self.decimals = min(max(decimals, 0), 3)
        self.showPercentageInMenuBar = showPercentageInMenuBar
        self.launchAtLogin = launchAtLogin
        self.restoreLastOutputDevice = restoreLastOutputDevice
        self.lastOutputDeviceUID = lastOutputDeviceUID
        self.hotkeysEnabled = hotkeysEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        presets = try container.decodeIfPresent([VolumePreset].self, forKey: .presets) ?? []
        decimals = min(max(try container.decodeIfPresent(Int.self, forKey: .decimals) ?? 1, 0), 3)
        showPercentageInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showPercentageInMenuBar) ?? false
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        restoreLastOutputDevice = try container.decodeIfPresent(Bool.self, forKey: .restoreLastOutputDevice) ?? false
        lastOutputDeviceUID = try container.decodeIfPresent(String.self, forKey: .lastOutputDeviceUID)
        hotkeysEnabled = try container.decodeIfPresent(Bool.self, forKey: .hotkeysEnabled) ?? true
    }
}
