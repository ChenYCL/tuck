import AppKit
import SwiftUI

/// A floating panel that shows a horizontal strip of hidden menu bar items, in lieu of
/// temporarily revealing them in place.
@MainActor
final class TuckBarPanel: NSPanel {
    private unowned let appState: AppState
    private var hostingView: NSHostingView<AnyView>?
    private var observers: [Any] = []

    private(set) var currentSection: MenuBarSection.Name?

    init(appState: AppState) {
        self.appState = appState
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        animationBehavior = .none
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .moveToActiveSpace]
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        allowsToolTipsWhenApplicationIsInactive = true

        configureObservers()
    }

    private func configureObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let center = NotificationCenter.default

        observers.append(workspaceCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        })

        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        })

        // The hidden-section divider's frame tracks the menu bar sliding in/out when the
        // system auto-hides it; if it slides away while we're showing, close the bar,
        // since we can no longer reliably display its items.
        observers.append(Observe.track { [weak self] in
            guard let self else { return }
            guard
                currentSection != nil,
                let hiddenFrame = appState.menuBarManager.section(named: .hidden)?.controlItem.windowFrame,
                let menuBarScreen = NSScreen.screens.first
            else { return }
            if hiddenFrame.maxY < menuBarScreen.visibleFrame.maxY {
                close()
            }
        })

        // Re-fit and reposition whenever the set of managed items changes.
        observers.append(Observe.track { [weak self] in
            guard let self else { return }
            _ = appState.itemStore.cache
            guard currentSection != nil, let hostingView, let screen else { return }
            Task { @MainActor [weak self] in
                self?.layoutContent(hostingView: hostingView, on: screen)
            }
        })
    }

    private func layoutContent(hostingView: NSHostingView<AnyView>, on screen: NSScreen) {
        let fitting = hostingView.fittingSize
        setContentSize(NSSize(width: min(fitting.width, screen.frame.width), height: fitting.height))
        updateOrigin(for: screen)
    }

    private func updateOrigin(for screen: NSScreen) {
        let originY = (screen.frame.maxY - 1) - screen.menuBarHeight - frame.height

        func clampedX(_ x: CGFloat) -> CGFloat {
            let lowerBound = screen.frame.minX
            let upperBound = screen.frame.maxX - frame.width
            guard lowerBound <= upperBound else { return screen.frame.maxX - frame.width }
            return x.clamped(to: lowerBound...upperBound)
        }

        func mousePointerX() -> CGFloat {
            clampedX(NSEvent.mouseLocation.x - frame.width / 2)
        }

        func tuckIconX() -> CGFloat {
            guard
                let windowID = appState.menuBarManager.section(named: .visible)?.controlItem.windowID,
                let cgFrame = Bridging.windowFrame(for: windowID),
                let primaryScreen = NSScreen.screens.first
            else {
                return mousePointerX()
            }
            // `Bridging.windowFrame` returns a Core Graphics frame with a top-left origin;
            // convert to AppKit's bottom-left origin before comparing against screen frames.
            let appKitY = primaryScreen.frame.height - cgFrame.origin.y - cgFrame.height
            let appKitFrame = CGRect(x: cgFrame.origin.x, y: appKitY, width: cgFrame.width, height: cgFrame.height)
            return clampedX(appKitFrame.midX - frame.width / 2)
        }

        let x: CGFloat
        switch appState.settings.tuckBarLocation {
        case .dynamic:
            x = appState.interaction.isMouseInsideEmptyMenuBarSpace ? mousePointerX() : tuckIconX()
        case .mousePointer:
            x = mousePointerX()
        case .tuckIcon:
            x = tuckIconX()
        }

        setFrameOrigin(CGPoint(x: x, y: originY))
    }

    func show(section: MenuBarSection.Name, on screen: NSScreen) async {
        // Important that navigation state and current section are set before updating the cache.
        appState.navigation.isTuckBarPresented = true
        currentSection = section

        await appState.itemStore.refreshIfNeeded()

        if ScreenCapture.cachedHasPermission() {
            await appState.imageCache.updateCache(sections: [section])
        }

        let hostingView = NSHostingView(rootView: AnyView(
            TuckBarView(section: section, screen: screen, panel: self).environment(appState)
        ))
        self.hostingView = hostingView
        contentView = hostingView

        layoutContent(hostingView: hostingView, on: screen)
        orderFrontRegardless()
    }

    override func close() {
        contentView = nil
        hostingView = nil
        currentSection = nil
        appState.navigation.isTuckBarPresented = false
        super.close()
    }
}
