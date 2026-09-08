import SwiftUI

/// Shown for menu bar items without a captured image: the source app's icon.
struct ItemFallbackIcon: View {
    let item: MenuBarItem
    var size: CGFloat = 18

    var body: some View {
        if let icon = item.owningApplication?.icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: size * 0.8))
                .foregroundStyle(.secondary)
        }
    }
}
