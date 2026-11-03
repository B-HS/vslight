import SwiftUI

struct VolumeCardView: View {
    @Environment(AppModel.self) private var model
    @State private var draft: String = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(model.audio.volumeText)
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: model.audio.volume))
                Text("%")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.toggleMute()
                } label: {
                    Image(systemName: model.audio.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.glass)
                .help(model.audio.isMuted ? "음소거 해제" : "음소거")
                .disabled(!model.audio.canSetMute)
            }

            Slider(
                value: Binding(
                    get: { model.audio.volume },
                    set: { model.setVolume($0) }
                ),
                in: 0...1
            )
            .controlSize(.large)
            .disabled(!model.audio.canSetVolume)

            HStack(spacing: 8) {
                Text("직접 입력")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("0.0", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 78)
                    .focused($isEditing)
                    .onSubmit(commit)
                    .onChange(of: isEditing) { _, focused in
                        if !focused {
                            commit()
                        }
                    }
                Text("%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("소수점 \(model.store.settings.decimals)자리")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .onAppear(perform: syncDraft)
        .onChange(of: model.audio.volume) { _, _ in
            if !isEditing {
                syncDraft()
            }
        }
        .onChange(of: model.store.settings.decimals) { _, _ in
            if !isEditing {
                syncDraft()
            }
        }
    }

    private func syncDraft() {
        draft = VolumeFormatter.percent(model.audio.volume, decimals: model.store.settings.decimals)
    }

    private func commit() {
        if let value = VolumeFormatter.parsePercent(draft) {
            model.setVolume(value)
        }
        syncDraft()
    }
}
