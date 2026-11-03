import AppKit
import SwiftUI

struct PerAppAudioView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                driverSection
                if model.perApp.driverInstalled {
                    controlsSection
                }
                if let error = model.perApp.lastError {
                    HStack(alignment: .top) {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                        Spacer()
                        Button("닫기") {
                            model.perApp.clearError()
                        }
                        .font(.caption)
                    }
                }
                processSection
            }
            .padding(18)
        }
        .onAppear {
            model.perApp.refresh()
        }
    }

    private var driverSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: model.perApp.driverInstalled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(model.perApp.driverInstalled ? .green : .orange)
                    Text(model.perApp.driverInstalled ? "가상 오디오 드라이버 설치됨" : "가상 오디오 드라이버가 필요합니다")
                        .font(.headline)
                    Spacer()
                    if model.perApp.driverInstalled {
                        Button("드라이버 제거") {
                            model.perApp.uninstallDriver()
                        }
                        .font(.caption)
                    } else {
                        Button("드라이버 설치") {
                            model.perApp.installDriver()
                        }
                        .font(.caption)
                    }
                }
                Text("앱별 게인은 시스템 출력과 모니터 출력 사이를 오가는 HAL 드라이버가 담당합니다. 설치는 관리자 승인이 필요하며 coreaudiod가 재시작됩니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private var controlsSection: some View {
        GroupBox("설정") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(
                    "앱별 볼륨 사용",
                    isOn: Binding(
                        get: { model.perApp.isEnabled },
                        set: { model.perApp.setEnabled($0) }
                    )
                )

                Picker(
                    "모니터 출력",
                    selection: Binding(
                        get: { model.perApp.monitorDevice?.uid ?? "" },
                        set: { uid in
                            if let device = model.perApp.realOutputDevices.first(where: { $0.uid == uid }) {
                                model.perApp.setMonitor(device)
                            }
                        }
                    )
                ) {
                    ForEach(model.perApp.realOutputDevices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                .pickerStyle(.menu)

                if model.perApp.isEnabled {
                    Text("시스템 출력이 VSLight Audio로 전환됩니다. 메뉴 바 볼륨은 전체 게인으로 동작합니다.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var processSection: some View {
        GroupBox("현재 오디오를 재생하는 앱") {
            if model.audio.processes.isEmpty {
                Text("재생 중인 앱이 없습니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 10) {
                    ForEach(model.audio.processes) { process in
                        processRow(process)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func processRow(_ process: AudioProcess) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: icon(for: process))
                .resizable()
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(process.name)
                    .font(.callout)
                if let bundleID = process.bundleID {
                    Text(bundleID)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 150, alignment: .leading)

            Slider(
                value: Binding(
                    get: { model.perApp.volume(for: process) },
                    set: { model.perApp.setVolume($0, for: process) }
                ),
                in: 0...1
            )
            .disabled(!model.perApp.isEnabled)

            Text(VolumeFormatter.percent(model.perApp.volume(for: process), decimals: 0) + "%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)

            Button {
                model.perApp.toggleMute(process)
            } label: {
                Image(systemName: model.perApp.isMuted(process) ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.perApp.isMuted(process) ? .primary : .secondary)
            .disabled(!model.perApp.isEnabled)
        }
    }

    private func icon(for process: AudioProcess) -> NSImage {
        if let bundleID = process.bundleID,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }
}
