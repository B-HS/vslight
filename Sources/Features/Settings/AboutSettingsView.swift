import AppKit
import SwiftUI

struct AboutSettingsView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)

            Text("VSLight")
                .font(.title2.weight(.semibold))
            Text("v\(AppVersion.short) (\(AppVersion.build))")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("macOS 27 전용 네이티브 볼륨 컨트롤")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Divider()
                .padding(.horizontal, 70)

            VStack(alignment: .leading, spacing: 6) {
                Label("소수점 단위 시스템 볼륨 제어", systemImage: "slider.horizontal.3")
                Label("프리셋별 전역 단축키", systemImage: "keyboard")
                Label("네이티브 출력 장치 선택", systemImage: "hifispeaker.2")
                Label("Liquid Glass 인터페이스", systemImage: "sparkles")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Button("GitHub에서 보기") {
                if let url = URL(string: "https://github.com/B-HS/vslight") {
                    openURL(url)
                }
            }
            .font(.caption)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
