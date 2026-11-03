import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("일반", systemImage: "slider.horizontal.3") }
            PresetsSettingsView()
                .tabItem { Label("프리셋", systemImage: "square.stack.3d.up") }
            PerAppAudioView()
                .tabItem { Label("앱별 볼륨", systemImage: "square.stack.3d.down.right") }
            AboutSettingsView()
                .tabItem { Label("정보", systemImage: "info.circle") }
        }
        .frame(width: 620, height: 480)
    }
}
