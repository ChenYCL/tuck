import AppKit
import SwiftUI

/// A floating panel that shows a horizontal or vertical strip of hidden menu bar items,
/// in lieu of temporarily revealing them in place.
@MainActor
final class TuckBarPanel: NSPanel {
    private unowned let appState: AppState
    private var hostingView: NSHostingView<AnyView>?
    private var observers: [Any] = []

    private(set) var currentSection: MenuBarSection.Name?

    private var isPinned: Bool {
        appState.settings.useTuckBar && appState.settings.tuckBarAlwaysVisible
    }

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
        isOpaque = false
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
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.isPinned {
                    Task { await self.refreshPinned() }
                } else {
                    self.close()
                }
            }
        })

        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.isPinned {
                    self.relayoutIfVisible()
                } else {
                    self.close()
                }
            }
        })

        // The hidden-section divider's frame tracks the menu bar sliding in/out when the
        // system auto-hides it; if it slides away while we're showing, close the bar,
        // since we can no longer reliably display its items. Pinned bars stay put.
        observers.append(Observe.track { [weak self] in
            guard let self else { return }
            guard
                !isPinned,
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
            guard currentSection != nil else { return }
            relayoutIfVisible()
        })

        observers.append(Observe.track { [weak self] in
            guard let self else { return }
            let useBar = appState.settings.useTuckBar
            let alwaysVisible = appState.settings.tuckBarAlwaysVisible
            _ = appState.settings.tuckBarLocation
            Task { @MainActor [weak self] in
                guard let self else { return }
                if useBar && alwaysVisible {
                    await self.showPinnedIfNeeded()
                } else if !useBar {
                    self.forceClose()
                } else {
                    self.relayoutIfVisible()
                }
            }
        })
    }

    private func relayoutIfVisible() {
        guard currentSection != nil, let hostingView else { return }
        guard let screen = screenForBar() ?? screen else { return }
        Task { @MainActor [weak self] in
            self?.layoutContent(hostingView: hostingView, on: screen)
        }
    }

    private func layoutContent(hostingView: NSHostingView<AnyView>, on screen: NSScreen) {
        let fitting = hostingView.fittingSize
        let maxWidth = screen.frame.width
        let maxHeight = max(screen.frame.height - screen.menuBarHeight - 8, 40)
        setContentSize(NSSize(
            width: min(max(fitting.width, 1), maxWidth),
            height: min(max(fitting.height, 1), maxHeight)
        ))
        updateOrigin(for: screen)
    }

    private func updateOrigin(for screen: NSScreen) {
        let location = appState.settings.tuckBarLocation
        let origin = TuckBarGeometry.origin(
            location: location,
            barSize: frame.size,
            screen: TuckBarGeometry.Screen(frame: screen.frame, menuBarHeight: screen.menuBarHeight),
            mouseX: NSEvent.mouseLocation.x,
            tuckIconMidX: (location == .tuckIcon || location == .dynamic) ? tuckIconMidX(on: screen) : nil,
            isMouseInEmptySpace: appState.interaction.isMouseInsideEmptyMenuBarSpace
        )
        setFrameOrigin(origin)
    }

    private func tuckIconMidX(on screen: NSScreen) -> CGFloat? {
        guard
            let windowID = appState.menuBarManager.section(named: .visible)?.controlItem.windowID,
            let cgFrame = Bridging.windowFrame(for: windowID),
            let primaryScreen = NSScreen.screens.first
        else {
            return nil
        }
        // `Bridging.windowFrame` returns a Core Graphics frame with a top-left origin;
        // convert to AppKit's bottom-left origin before comparing against screen frames.
        let appKitY = primaryScreen.frame.height - cgFrame.origin.y - cgFrame.height
        let appKitFrame = CGRect(x: cgFrame.origin.x, y: appKitY, width: cgFrame.width, height: cgFrame.height)
        guard screen.frame.intersects(appKitFrame) else { return nil }
        return appKitFrame.midX
    }

    func showPinnedIfNeeded() async {
        guard isPinned else { return }
        if currentSection != nil {
            relayoutIfVisible()
            return
        }
        await refreshPinned()
    }

    private func screenForBar() -> NSScreen? {
        NSScreen.screenWithActiveMenuBar ?? NSScreen.screens.first ?? NSScreen.main
    }

    private func refreshPinned() async {
        guard isPinned else { return }
        guard let screen = screenForBar() else { return }
        await show(section: .hidden, on: screen)
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
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        self.hostingView = hostingView
        contentView = hostingView

        layoutContent(hostingView: hostingView, on: screen)
        orderFrontRegardless()
    }

    override func close() {
        if isPinned { return }
        forceClose()
    }

    func forceClose() {
        contentView = nil
        hostingView = nil
        currentSection = nil
        appState.navigation.isTuckBarPresented = false
        super.close()
    }
}
