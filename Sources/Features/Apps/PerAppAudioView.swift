import AppKit
import SwiftUI

struct PerAppAudioView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("앱별 볼륨에는 가상 오디오 드라이버가 필요합니다", systemImage: "info.circle")
                            .font(.headline)
                        Text("macOS 공개 API는 다른 앱의 출력 볼륨을 직접 낮출 수 없습니다. 프로세스 탭은 캡처 전용이라 감쇠를 적용할 수 없고, 앱별 게인을 적용하려면 HAL 오디오 드라이버를 설치해야 합니다.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("v0.1은 시스템 출력 볼륨과 장치 선택, 프리셋 단축키를 제공하고, 이 화면에서는 현재 오디오를 재생하는 앱만 보여줍니다.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }

                GroupBox("현재 오디오를 재생하는 앱") {
                    if model.audio.processes.isEmpty {
                        Text("재생 중인 앱이 없습니다.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(model.audio.processes) { process in
                                row(for: process)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(20)
        }
        .onAppear {
            model.audio.refreshProcesses()
        }
    }

    private func row(for process: AudioProcess) -> some View {
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
            Spacer()
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .help("앱별 볼륨은 드라이버 단계에서 지원합니다.")
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
