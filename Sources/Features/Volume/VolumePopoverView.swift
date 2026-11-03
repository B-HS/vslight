import AppKit
import SwiftUI

struct VolumePopoverView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 14) {
            header
            VolumeCardView()
            OutputDeviceMenu()
            PresetChipsView()
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 344)
        .task {
            model.start()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("VSLight")
                    .font(.headline)
                Text(model.audio.deviceName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                NSApplication.shared.activate()
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.glass)
            .help("설정 열기")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.glass)
            .help("종료")
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("v\(model.versionText)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            if let error = model.audio.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
    }
}
