import SwiftUI

struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: model.audio.menuBarSymbol, variableValue: model.audio.volume)
            if model.store.settings.showPercentageInMenuBar {
                Text(VolumeFormatter.percent(model.audio.volume, decimals: model.store.settings.decimals) + "%")
                    .monospacedDigit()
            }
        }
    }
}
