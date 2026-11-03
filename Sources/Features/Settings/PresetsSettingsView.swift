import SwiftUI

struct PresetsSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var store = model.store
        VStack(spacing: 0) {
            List {
                ForEach($store.settings.presets) { $preset in
                    PresetRow(preset: $preset)
                        .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                }
                .reorderable()
                .onDelete { offsets in
                    store.settings.presets.remove(atOffsets: offsets)
                    model.applyHotkeys()
                }
                .onMove { source, destination in
                    store.settings.presets.move(fromOffsets: source, toOffset: destination)
                }
            }
            .listStyle(.inset)

            HStack(spacing: 10) {
                Button("프리셋 추가") {
                    store.settings.presets.append(VolumePreset(name: "새 프리셋", volume: 0.5))
                    model.applyHotkeys()
                }
                Spacer()
                Text("\(store.settings.presets.count)개")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
        }
        .onChange(of: store.settings.presets.map(\.hotkey)) { _, _ in
            model.applyHotkeys()
        }
    }
}

struct PresetRow: View {
    @Binding var preset: VolumePreset
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            TextField("이름", text: $preset.name)
                .textFieldStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                .frame(width: 126)

            Slider(value: $preset.volume, in: 0...1)
                .frame(minWidth: 110)

            Text(preset.volumeText + "%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .trailing)

            HotkeyRecorderView(hotkey: $preset.hotkey)

            if let failure = model.hotkeyFailure(for: preset) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(failure)
            }
        }
        .frame(minHeight: 34)
    }
}
