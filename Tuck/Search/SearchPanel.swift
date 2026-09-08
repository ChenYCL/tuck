import AppKit
import SwiftUI

/// A panel that presents the menu bar item search interface.
@MainActor
final class SearchPanel: NSPanel {
    /// The default screen to show the panel on.
    static var defaultScreen: NSScreen? {
        NSScreen.screenWithMouse ?? NSScreen.main
    }

    private unowned let appState: AppState
    private var mouseDownMonitor: EventMonitor?
    private var keyDownMonitor: EventMonitor?

    override var canBecomeKey: Bool { true }

    init(appState: AppState) {
        self.appState = appState
        super.init(
            contentRect: .zero,
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .moveToActiveSpace]
        backgroundColor = .clear
        isMovableByWindowBackground = true
    }

    /// Shows the search panel on the given screen.
    func show(on screen: NSScreen) async {
        // Important that we set the navigation state before updating the caches.
        appState.navigation.isSearchPresented = true

        await appState.itemStore.refreshIfNeeded()
        if ScreenCapture.cachedHasPermission() {
            await appState.imageCache.updateCache(sections: MenuBarSection.Name.allCases)
        }

        contentView = NSHostingView(rootView: SearchView(panel: self).environment(appState))

        let size = CGSize(width: 560, height: 420)
        let origin = CGPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY + size.height / 2 + screen.frame.height / 8
        )
        setFrame(CGRect(origin: origin, size: size), display: true)

        makeKeyAndOrderFront(nil)

        let mouseDownMonitor = EventMonitor(
            mask: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
            scope: .universal
        ) { [weak self] event in
            guard let self, event.window !== self else { return event }
            if !self.appState.itemMover.isMovingItem {
                self.close()
            }
            return event
        }
        mouseDownMonitor.start()
        self.mouseDownMonitor = mouseDownMonitor

        let keyDownMonitor = EventMonitor(mask: [.keyDown], scope: .local) { [weak self] event in
            if KeyCode(rawValue: Int(event.keyCode)) == .escape {
                self?.close()
                return nil
            }
            return event
        }
        keyDownMonitor.start()
        self.keyDownMonitor = keyDownMonitor
    }

    /// Toggles the panel's visibility.
    func toggle() {
        if isVisible {
            close()
        } else if let screen = Self.defaultScreen {
            Task { await show(on: screen) }
        }
    }

    /// Dismisses the search panel.
    override func close() {
        mouseDownMonitor?.stop()
        mouseDownMonitor = nil
        keyDownMonitor?.stop()
        keyDownMonitor = nil
        contentView = nil
        appState.navigation.isSearchPresented = false
        super.close()
    }
}
