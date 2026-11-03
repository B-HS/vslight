import SwiftUI

struct OutputDeviceMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            ForEach(model.audio.devices) { device in
                Button {
                    model.select(device)
                } label: {
                    Label(
                        "\(device.name) · \(device.transport.label)",
                        systemImage: device.id == model.audio.defaultDeviceID ? "checkmark" : device.transport.symbolName
                    )
                }
            }
            Divider()
            Button("사운드 설정 열기") {
                model.openSoundSettings()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: model.audio.currentDevice?.transport.symbolName ?? "hifispeaker")
                    .font(.system(size: 14, weight: .medium))
                Text(model.audio.deviceName)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Image(systemName: "arrow.up.arrow.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }
}
