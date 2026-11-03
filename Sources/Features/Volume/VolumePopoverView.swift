import AppKit
import SwiftUI

struct VolumePopoverView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                OutputDeviceMenu()
                Spacer(minLength: 0)
                iconButton("gearshape", help: "설정") {
                    model.settingsTab = .general
                    NSApplication.shared.activate()
                    openSettings()
                }
                iconButton("power", help: "종료") {
                    NSApplication.shared.terminate(nil)
                }
            }
            VolumeCardView()
            PresetChipsView()
            if let error = model.audio.lastError {
                HStack(spacing: 4) {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button {
                        model.clearError()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(width: 304)
        .task {
            model.start()
        }
    }

    private func iconButton(_ name: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }
}
