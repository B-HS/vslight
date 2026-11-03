import SwiftUI

struct PresetChipsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("프리셋")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("클릭하여 적용")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if model.store.settings.presets.isEmpty {
                Text("설정에서 프리셋을 추가하세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.store.settings.presets) { preset in
                            Button {
                                model.apply(preset)
                            } label: {
                                VStack(spacing: 2) {
                                    Text(preset.name)
                                        .font(.caption.weight(.medium))
                                        .lineLimit(1)
                                    Text(preset.volumeText + "%")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.glass)
                            .help(preset.hotkey.map { "단축키 \($0.displayString)" } ?? "단축키 없음")
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}
