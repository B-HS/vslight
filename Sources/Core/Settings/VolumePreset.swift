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

    var volumeText: String {
        VolumeFormatter.percent(volume, decimals: 1)
    }

    static let defaults: [VolumePreset] = [
        VolumePreset(name: "조용히", volume: 0.2),
        VolumePreset(name: "보통", volume: 0.5),
        VolumePreset(name: "크게", volume: 0.8),
        VolumePreset(name: "최대", volume: 1.0)
    ]
}
