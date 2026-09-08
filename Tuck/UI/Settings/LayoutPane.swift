import AppKit
import SwiftUI

/// The "Menu Bar Layout" settings pane, allowing the user to drag items between sections.
struct LayoutPane: View {
    @Environment(AppState.self) private var appState
    @State private var drag = LayoutDragController()

    var body: some View {
        Group {
            if appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults {
                Text("Tuck cannot arrange items in automatically hidden menu bars")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                layoutForm
            }
        }
        .environment(drag)
        .coordinateSpace(name: "layout")
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            // A drag can't finish once another app takes focus; clear the ghost.
            drag.reset()
        }
        .onDisappear { drag.reset() }
        .overlay(alignment: .topLeading) { dragGhost }
        .alert("Error", isPresented: Binding(
            get: { drag.errorMessage != nil },
            set: { if !$0 { drag.errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(drag.errorMessage ?? "")
        }
    }

    private var layoutForm: some View {
        Form {
            Section {
                Text("Drag to arrange your menu bar items")
                Text("You can also ⌘-drag items directly in the menu bar")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if !ScreenCapture.cachedHasPermission() {
                    Text("Grant screen recording permission in Advanced settings to see item previews instead of app icons")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(appState.menuBarManager.sections.filter(\.isEnabled), id: \.name) { section in
                Section("\(section.name.displayName) Section") {
                    LayoutBarView(section: section.name)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var dragGhost: some View {
        if let item = drag.draggingItem {
            ghostContent(for: item)
                .position(drag.dragLocation)
                .allowsHitTesting(false)
                .shadow(radius: 6)
        }
    }

    @ViewBuilder
    private func ghostContent(for item: MenuBarItem) -> some View {
        if let cgImage = appState.imageCache.images[item.info] {
            let scale = 1 / (appState.imageCache.screen?.backingScaleFactor ?? 2)
            let size = NSSize(width: CGFloat(cgImage.width) * scale, height: CGFloat(cgImage.height) * scale)
            Image(nsImage: NSImage(cgImage: cgImage, size: size))
                .resizable()
                .frame(width: size.width, height: size.height)
        } else {
            Text(item.displayName)
                .font(.caption2)
        }
    }
}
