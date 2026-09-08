import SwiftUI

struct PaneIcon: View {
    let pane: SettingsPane

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(pane.tint.gradient)
            .frame(width: 24, height: 24)
            .overlay {
                Image(systemName: pane.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
            }
    }
}
