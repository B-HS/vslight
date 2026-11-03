import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var store = model.store
        Form {
            Section("표시") {
                Picker("소수점 자리", selection: $store.settings.decimals) {
                    ForEach(0...3, id: \.self) { digits in
                        Text("\(digits)자리").tag(digits)
                    }
                }
                Toggle("메뉴 막대에 퍼센트 표시", isOn: $store.settings.showPercentageInMenuBar)
            }

            Section("동작") {
                Toggle("프리셋 단축키 사용", isOn: $store.settings.hotkeysEnabled)
                    .onChange(of: store.settings.hotkeysEnabled) { _, _ in
                        model.applyHotkeys()
                    }
                Toggle("마지막 출력 장치 복원", isOn: $store.settings.restoreLastOutputDevice)
                Toggle(
                    "로그인 시 실행",
                    isOn: Binding(
                        get: { model.isLaunchAtLoginEnabled },
                        set: { model.setLaunchAtLogin($0) }
                    )
                )
            }

            Section("출력 장치") {
                LabeledContent("현재 장치", value: model.audio.deviceName)
                Button("사운드 설정 열기") {
                    model.openSoundSettings()
                }
            }

            if let error = model.lastErrorMessage {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }
}
