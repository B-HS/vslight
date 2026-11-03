import Foundation

struct VolumePreset: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var volume: Double
    var deviceUID: String?
    var hotkey: Hotkey?

    init(
        id: UUID = UUID(),
        name: String,
        volume: Double,
        deviceUID: String? = nil,
        hotkey: Hotkey? = nil
    ) {
        self.id = id
        self.name = name
        self.volume = min(max(volume, 0), 1)
        self.deviceUID = deviceUID
        self.hotkey = hotkey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? String(localized: "프리셋")
        let decodedVolume = try container.decodeIfPresent(Double.self, forKey: .volume) ?? 0.5
        volume = min(max(decodedVolume, 0), 1)
        deviceUID = try container.decodeIfPresent(String.self, forKey: .deviceUID)
        hotkey = try container.decodeIfPresent(Hotkey.self, forKey: .hotkey)
    }

    var volumeText: String {
        VolumeFormatter.percent(volume, decimals: 1)
    }
}
