import SwiftUI

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 52, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)

            Text("VSLight")
                .font(.title2.weight(.semibold))
            Text("v\(AppVersion.short) (\(AppVersion.build))")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("macOS 27 전용 네이티브 볼륨 컨트롤")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Divider()
                .padding(.horizontal, 60)

            VStack(alignment: .leading, spacing: 6) {
                Label("소수점 단위 시스템 볼륨 제어", systemImage: "slider.horizontal.3")
                Label("프리셋별 전역 단축키", systemImage: "keyboard")
                Label("네이티브 출력 장치 선택", systemImage: "hifispeaker.2")
                Label("Liquid Glass 인터페이스", systemImage: "sparkles")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.top, 4)

            Spacer(minLength: 8)

            Text("버전 번호에는 숫자 4를 사용하지 않습니다. 릴리스는 0.1.0, 0.2.0, 0.3.0, 0.5.0 순서로 진행합니다.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
