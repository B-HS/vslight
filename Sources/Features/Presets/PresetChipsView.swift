import AppKit
import SwiftUI

struct PresetChipsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if model.store.settings.presets.isEmpty {
            Button {
                openPresetSettings()
            } label: {
                Label("프리셋 추가", systemImage: "plus")
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .background(.quaternary.opacity(0.45), in: Capsule())
            .help("설정에서 프리셋을 만듭니다.")
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.store.settings.presets) { preset in
                        Button {
                            model.apply(preset)
                        } label: {
                            HStack(spacing: 4) {
                                Text(preset.name)
                                    .font(.caption.weight(.medium))
                                Text(preset.volumeText + "%")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .background(.quaternary.opacity(0.45), in: Capsule())
                        .help(preset.hotkey.map { String(localized: "단축키") + " \($0.displayString)" } ?? String(localized: "단축키 없음"))
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private func openPresetSettings() {
        model.settingsTab = .presets
        NSApplication.shared.activate()
        openSettings()
    }
}
