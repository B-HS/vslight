import AppKit
import SwiftUI

struct VolumeCardView: View {
    @Environment(AppModel.self) private var model
    @State private var draft: String = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 46, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 132, alignment: .trailing)
                    .padding(.horizontal, 4)
                    .background {
                        if isEditing {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.quaternary.opacity(0.6))
                        }
                    }
                    .focused($isEditing)
                    .onSubmit(commit)
                    .onChange(of: isEditing) { _, focused in
                        if focused {
                            syncDraft()
                            Task { @MainActor in
                                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                            }
                        } else {
                            commit()
                        }
                    }

                Text("%")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Button {
                    model.toggleMute()
                } label: {
                    Image(systemName: model.audio.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.audio.isMuted ? .primary : .secondary)
                .disabled(!model.audio.canSetMute)
                .help(model.audio.isMuted ? "음소거 해제" : "음소거")
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
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
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
        if let value = VolumeFormatter.parsePercent(draft), abs(value - model.audio.volume) > 0.0005 {
            model.setVolume(value)
        }
        syncDraft()
        isEditing = false
    }
}
