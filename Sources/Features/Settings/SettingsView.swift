import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            GeneralSettingsView()
                .tabItem { Label("일반", systemImage: "slider.horizontal.3") }
                .tag(SettingsTab.general)
            PresetsSettingsView()
                .tabItem { Label("프리셋", systemImage: "square.stack.3d.up") }
                .tag(SettingsTab.presets)
            PerAppAudioView()
                .tabItem { Label("앱별 볼륨", systemImage: "square.stack.3d.down.right") }
                .tag(SettingsTab.perApp)
            AboutSettingsView()
                .tabItem { Label("정보", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 560, height: 440)
    }
}
