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
            }

            Section("시작") {
                LaunchAtLoginSettingsView()
            }

            Section("출력 장치") {
                LabeledContent("현재 장치", value: model.audio.deviceName)
                Button("사운드 설정 열기") {
                    model.openSoundSettings()
                }
                Button("오디오 다시 감지") {
                    model.audio.restartMonitoring()
                    model.applyHotkeys()
                    model.refreshLaunchAtLoginState()
                }
                .help("잠자기에서 깨어난 뒤 오디오 상태가 갱신되지 않을 때 사용합니다.")
            }

            if let error = model.lastErrorMessage {
                Section {
                    HStack(alignment: .top) {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                        Spacer()
                        Button("닫기") {
                            model.clearError()
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }
}

struct LaunchAtLoginSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var isOn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("로그인 시 실행", isOn: $isOn)
                .onChange(of: isOn) { _, newValue in
                    if newValue != model.launchAtLoginState.isOn {
                        model.setLaunchAtLogin(newValue)
                    }
                }

            HStack(spacing: 6) {
                Image(systemName: model.launchAtLoginState.symbolName)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                Text(model.launchAtLoginState.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("다시 확인") {
                    model.refreshLaunchAtLoginState()
                }
                .font(.caption)
                .help("등록 상태를 다시 읽습니다.")

                Button("앱 재시작") {
                    model.restartApp()
                }
                .font(.caption)
                .help("로그인 항목 변경을 적용하기 위해 앱을 다시 시작합니다.")
            }

            if let detail = model.launchAtLoginState.detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.launchAtLoginState == .requiresApproval {
                Button("시스템 설정에서 승인") {
                    model.openLoginItemsSettings()
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 2)
        .onAppear {
            isOn = model.launchAtLoginState.isOn
        }
        .onChange(of: model.launchAtLoginState) { _, state in
            if isOn != state.isOn {
                isOn = state.isOn
            }
        }
    }

    private var statusColor: Color {
        switch model.launchAtLoginState {
        case .enabled: .green
        case .requiresApproval: .orange
        case .notRegistered: .gray
        case .notFound: .orange
        }
    }
}
