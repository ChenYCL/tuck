import AppKit
import OSLog

/// A borderless, mouse-transparent panel that sits atop the real menu bar on one screen,
/// drawing the configured tint, shadow, border, and shape. One instance exists per screen,
/// owned and torn down by `AppearanceManager`.
@MainActor
final class OverlayPanel: NSPanel {
    unowned let appState: AppState
    let owningScreen: NSScreen

    /// The frame of the frontmost app's application menu, used by the split shape.
    private(set) var applicationMenuFrame: CGRect?

    /// The area of the desktop wallpaper under the menu bar, used by the full/split shapes.
    private(set) var desktopWallpaper: CGImage?

    private static let interfaceThemeChangedNotification = Notification.Name("AppleInterfaceThemeChangedNotification")

    private var observers: [Any] = []
    private var leftMouseUpMonitor: EventMonitor?

    private var pendingShow: Task<Void, Never>?
    private var pendingThemeChange: Task<Void, Never>?
    private var pendingAppMenuFrameUpdate: Task<Void, Never>?
    private var themeChangeWallpaperTask: Task<Void, Never>?
    private var appMenuFramePollTask: Task<Void, Never>?
    private var wallpaperTimer: Timer?
    private var appMenuFrameFallbackTimer: Timer?

    init(appState: AppState, owningScreen: NSScreen) {
        self.appState = appState
        self.owningScreen = owningScreen
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .statusBar
        title = "Menu Bar Overlay"
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        hidesOnDeactivate = false
        canHide = false
        isMovable = false
        ignoresMouseEvents = true
        isExcludedFromWindowsMenu = true
        isReleasedWhenClosed = false
        collectionBehavior = [.fullScreenNone, .ignoresCycle, .moveToActiveSpace]
        setAccessibilityElement(false)
        contentView = OverlayContentView()

        configureObservers()
    }

    private func configureObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter

        // Panels don't persist visually across Spaces reliably; re-show on the new one.
        observers.append(workspaceCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleShow(after: .milliseconds(100)) }
        })

        // Wallpaper crossfades on a light/dark toggle take a moment to settle; keep
        // re-sampling for a few seconds afterward.
        observers.append(DistributedNotificationCenter.default().addObserver(forName: Self.interfaceThemeChangedNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleThemeChangeWallpaperResample() }
        })

        observers.append(NSWorkspace.shared.observe(\.frontmostApplication, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.startApplicationMenuFramePoll() }
        })

        // Catches cases (e.g. clicking into another Space) that don't otherwise post a
        // frontmost-application change.
        leftMouseUpMonitor = EventMonitor(mask: .leftMouseUp, scope: .global) { [weak self] event in
            self?.scheduleAppMenuFrameUpdate(after: .milliseconds(50))
            return event
        }
        leftMouseUpMonitor?.start()

        // Fade out immediately (not `orderOut`) when the system hides the real menu bar
        // (fullscreen presentation options, mouse away from the top edge), so the overlay
        // doesn't visually clash with whatever's behind it.
        observers.append(Observe.track { [weak self] in
            guard let self else { return }
            alphaValue = appState.menuBarManager.isMenuBarHiddenBySystem ? 0 : 1
        })

        // The wallpaper and application-menu-frame timers are the only periodic polling
        // this panel does; both are gated to the shape kinds that actually need them.
        observers.append(Observe.track { [weak self] in
            guard let self else { return }
            let shapeKind = appState.appearance.configuration.shapeKind
            updateWallpaperTimer(active: shapeKind != .none)
            updateAppMenuFrameFallbackTimer(active: shapeKind == .split)
        })
    }

    // MARK: - Show

    private func scheduleShow(after delay: Duration) {
        pendingShow?.cancel()
        pendingShow = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            self?.show()
        }
    }

    func show() {
        guard
            !appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults,
            !appState.menuBarManager.isActiveSpaceFullscreen,
            ApplicationMenu.hasValidMenuBar(for: owningScreen.displayID)
        else {
            Logger.overlayPanel.debug("Preventing overlay panel from showing")
            return
        }

        let menuBarHeight = WindowInfo.menuBarWindow(for: owningScreen.displayID)?.frame.height ?? owningScreen.menuBarHeight
        let newFrame = CGRect(
            x: owningScreen.frame.minX,
            y: owningScreen.frame.maxY - menuBarHeight - 5,
            width: owningScreen.frame.width,
            height: menuBarHeight + 5
        )
        setFrame(newFrame, display: false)
        alphaValue = appState.menuBarManager.isMenuBarHiddenBySystem ? 0 : 1
        orderFrontRegardless()

        updateApplicationMenuFrame()
        Task { [weak self] in
            await self?.updateDesktopWallpaper()
        }
    }

    // MARK: - Redraw

    func setNeedsDisplay() {
        contentView?.needsDisplay = true
    }

    func setIsDraggingMenuBarItem(_ isDragging: Bool) {
        contentView?.animator().alphaValue = isDragging ? 0 : 1
    }

    // MARK: - Application menu frame

    private func updateApplicationMenuFrame() {
        guard !appState.menuBarManager.isMenuBarHiddenBySystem else { return }
        let frame = ApplicationMenu.frame(for: owningScreen.displayID)
        guard frame != applicationMenuFrame else { return }
        applicationMenuFrame = frame
        setNeedsDisplay()
    }

    private func scheduleAppMenuFrameUpdate(after delay: Duration) {
        pendingAppMenuFrameUpdate?.cancel()
        pendingAppMenuFrameUpdate = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.updateApplicationMenuFrame()
        }
    }

    /// Polls for a fresh application menu frame every 50ms, for up to 2 seconds, after the
    /// frontmost app changes. Only the main screen shows the application menu.
    private func startApplicationMenuFramePoll() {
        guard owningScreen == NSScreen.main else { return }
        appMenuFramePollTask?.cancel()
        let displayID = owningScreen.displayID
        let priorFrame = applicationMenuFrame
        appMenuFramePollTask = Task { [weak self] in
            try? await withTimeout(.seconds(2)) {
                while true {
                    try Task.checkCancellation()
                    if let latest = ApplicationMenu.frame(for: displayID), latest != priorFrame {
                        self?.applicationMenuFrame = latest
                        self?.setNeedsDisplay()
                        return
                    }
                    try await Task.sleep(for: .milliseconds(50))
                }
            }
        }
    }

    private func updateAppMenuFrameFallbackTimer(active: Bool) {
        guard active else {
            appMenuFrameFallbackTimer?.invalidate()
            appMenuFrameFallbackTimer = nil
            return
        }
        guard appMenuFrameFallbackTimer == nil else { return }
        appMenuFrameFallbackTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateApplicationMenuFrame() }
        }
    }

    // MARK: - Desktop wallpaper

    private func updateDesktopWallpaper() async {
        let displayID = owningScreen.displayID
        guard
            let wallpaperWindow = WindowInfo.wallpaperWindow(for: displayID),
            let menuBarWindow = WindowInfo.menuBarWindow(for: displayID)
        else {
            return
        }
        let windowID = wallpaperWindow.windowID
        let screenBounds = menuBarWindow.frame
        let wallpaper = await Task.detached(priority: .utility) {
            ScreenCapture.captureWindows([windowID], screenBounds: screenBounds)
        }.value
        guard desktopWallpaper?.dataProvider?.data != wallpaper?.dataProvider?.data else { return }
        desktopWallpaper = wallpaper
        setNeedsDisplay()
    }

    private func scheduleThemeChangeWallpaperResample() {
        pendingThemeChange?.cancel()
        pendingThemeChange = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self?.startThemeChangeWallpaperResampling()
        }
    }

    private func startThemeChangeWallpaperResampling() {
        themeChangeWallpaperTask?.cancel()
        themeChangeWallpaperTask = Task { [weak self] in
            try? await withTimeout(.seconds(5)) {
                while true {
                    try Task.checkCancellation()
                    await self?.updateDesktopWallpaper()
                    try await Task.sleep(for: .seconds(1))
                }
            }
        }
    }

    private func updateWallpaperTimer(active: Bool) {
        guard active else {
            wallpaperTimer?.invalidate()
            wallpaperTimer = nil
            return
        }
        guard wallpaperTimer == nil else { return }
        wallpaperTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.fireWallpaperTimer() }
        }
    }

    private func fireWallpaperTimer() {
        Task { [weak self] in
            await self?.updateDesktopWallpaper()
        }
    }

    // MARK: - Teardown

    override func close() {
        pendingShow?.cancel()
        pendingThemeChange?.cancel()
        pendingAppMenuFrameUpdate?.cancel()
        themeChangeWallpaperTask?.cancel()
        appMenuFramePollTask?.cancel()
        wallpaperTimer?.invalidate()
        appMenuFrameFallbackTimer?.invalidate()
        leftMouseUpMonitor?.stop()
        observers.removeAll()
        contentView = nil
        super.close()
    }
}

nonisolated private extension Logger {
    static let overlayPanel = Logger(category: "OverlayPanel")
}
