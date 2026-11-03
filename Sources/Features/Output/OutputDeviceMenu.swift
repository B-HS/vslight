import SwiftUI

struct OutputDeviceMenu: View {
    @Environment(AppModel.self) private var model

    private var availableDevices: [AudioDevice] {
        model.audio.devices.filter { device in
            device.uid != PerAppVolumeController.driverUID || model.perApp.isEnabled
        }
    }

    var body: some View {
        Menu {
            if availableDevices.isEmpty {
                Text("출력 장치 없음")
            } else {
                ForEach(availableDevices) { device in
                    Button {
                        model.select(device)
                    } label: {
                        if device.id == model.audio.defaultDeviceID {
                            Label(device.name, systemImage: "checkmark")
                        } else {
                            Label(
                                "\(device.name) · \(device.transport.label)",
                                systemImage: device.transport.symbolName
                            )
                        }
                    }
                }
            }
            Divider()
            Button("사운드 설정 열기") {
                model.openSoundSettings()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: model.audio.currentDevice?.transport.symbolName ?? "hifispeaker")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(model.audio.deviceName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("출력 장치 선택")
    }
}
