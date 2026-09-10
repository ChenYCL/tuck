import AppKit
import SwiftUI

/// Vector / high-resolution icon for the Dock-style edge bar.
/// Never uses menu-bar screenshots — those are 1x-ish captures and look soft.
enum DockItemIcon {
    static func symbolName(title: String, displayName: String, namespace: String?) -> String? {
        let blob = (title + " " + displayName + " " + (namespace ?? "")).lowercased()

        if blob.contains("wifi") || blob.contains("wi-fi") || blob.contains("wi‑fi") { return "wifi" }
        if blob.contains("battery") { return "battery.100percent" }
        if blob.contains("bluetooth") { return "point.3.connected.trianglepath.point" }
        if blob.contains("sound") || blob.contains("volume") || blob.contains("speaker") { return "speaker.wave.2.fill" }
        if blob.contains("nowplaying") || blob.contains("now playing") { return "play.circle.fill" }
        if blob.contains("focus") || blob.contains("do not disturb") { return "moon.fill" }
        if blob.contains("airdrop") { return "airplayaudio" }
        if blob.contains("screenmirroring") || blob.contains("screen mirroring") || blob.contains("airplay") { return "airplayvideo" }
        if blob.contains("display") { return "display" }
        if blob.contains("clock") { return "clock.fill" }
        if blob.contains("controlcenter") || blob.contains("control center") || blob.contains("bentobox") { return "switch.2" }
        if blob.contains("stagemanager") || blob.contains("stage manager") { return "rectangle.split.2x1" }
        if blob.contains("hearing") { return "ear" }
        if blob.contains("keyboard") { return "keyboard" }
        if blob.contains("accessibility") { return "accessibility" }
        if blob.contains("user") { return "person.crop.circle" }
        if blob.contains("vpn") { return "network" }
        if blob.contains("time machine") || blob.contains("timemachine") { return "clock.arrow.circlepath" }
        return nil
    }

    static func symbolName(for item: MenuBarItem) -> String? {
        if item.isControlItem { return "gearshape" }
        return symbolName(title: item.info.title, displayName: item.displayName, namespace: item.info.namespace.rawValue)
    }

    static func applicationIcon(for item: MenuBarItem, pointSize: CGFloat) -> NSImage? {
        let app = item.owningApplication
        let path = app?.bundleURL?.path
            ?? app?.bundleIdentifier.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)?.path }
        let icon: NSImage
        if let path {
            icon = NSWorkspace.shared.icon(forFile: path)
        } else if let appIcon = app?.icon {
            icon = appIcon
        } else {
            return nil
        }
        let pixels = max(pointSize * 2, 128)
        icon.size = NSSize(width: pixels, height: pixels)
        return icon
    }
}

struct DockItemIconView: View {
    let item: MenuBarItem
    let size: CGFloat

    var body: some View {
        Group {
            if let symbol = DockItemIcon.symbolName(for: item) {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
            } else if let icon = DockItemIcon.applicationIcon(for: item, pointSize: size) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(width: size * 0.86, height: size * 0.86)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: size * 0.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .help(item.displayName)
        .accessibilityLabel(item.displayName)
    }
}
