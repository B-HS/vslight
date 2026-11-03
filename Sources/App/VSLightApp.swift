import SwiftUI

@main
struct VSLightApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            VolumePopoverView()
                .environment(model)
        } label: {
            MenuBarLabel()
                .environment(model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
