import AppKit
import SwiftUI

/// A draggable circular button. Click reveals the Tuck Bar; it is not shown until then.
@MainActor
final class FloatingHandlePanel: NSPanel {
    private unowned let appState: AppState
    private var observers: [Any] = []

    init(appState: AppState) {
        self.appState = appState
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        animationBehavior = .utilityWindow
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        allowsToolTipsWhenApplicationIsInactive = true

        configureObservers()
    }

    /// AppKit otherwise pins the window to the screen it started on.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        let specs = NSScreen.screens.map {
            FloatingHandleGeometry.ScreenSpec(frame: $0.frame, menuBarHeight: $0.menuBarHeight)
        }
        let probe = CGPoint(x: frameRect.midX, y: frameRect.midY)
        guard let spec = FloatingHandleGeometry.screenContaining(probe, screens: specs) else {
            return frameRect
        }
        let bounds = FloatingHandleGeometry.movableBounds(
            size: frameRect.size.width,
            screen: spec.frame,
            menuBarHeight: spec.menuBarHeight
        )
        var origin = frameRect.origin
        if bounds.width > 0 {
            origin.x = origin.x.clamped(to: bounds.minX...bounds.maxX)
        }
        if bounds.height > 0 {
            origin.y = origin.y.clamped(to: bounds.minY...bounds.maxY)
        }
        return NSRect(origin: origin, size: frameRect.size)
    }

    private func configureObservers() {
        observers.append(Observe.track { [weak self] in
            guard let self else { return }
            let use = appState.settings.useTuckBar
            let show = appState.settings.showFloatingHandle
            _ = appState.settings.floatingHandleSize
            _ = appState.settings.floatingHandleIcon
            Task { @MainActor [weak self] in
                guard let self else { return }
                if use && show {
                    self.present()
                } else {
                    self.orderOut(nil)
                }
            }
        })

        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyStoredFrame() }
        })
    }

    func present() {
        let size = CGFloat(appState.settings.floatingHandleSize)
        let hosting = NSHostingView(rootView: AnyView(
            FloatingHandleView(panel: self).environment(appState)
        ))
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        hosting.layer?.isOpaque = false
        hosting.layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: size, height: size))

        let clip = NSView(frame: hosting.frame)
        clip.wantsLayer = true
        clip.layer?.backgroundColor = .clear
        clip.layer?.isOpaque = false
        clip.layer?.cornerRadius = size / 2
        clip.layer?.masksToBounds = true
        clip.layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        hosting.autoresizingMask = [.width, .height]
        clip.addSubview(hosting)

        contentView = clip
        setContentSize(NSSize(width: size, height: size))
        applyCircleClip(size: size)
        applyStoredFrame()
        orderFrontRegardless()
    }

    private func applyCircleClip(size: CGFloat) {
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        contentView?.wantsLayer = true
        contentView?.layer?.backgroundColor = .clear
        contentView?.layer?.isOpaque = false
        contentView?.layer?.cornerRadius = size / 2
        contentView?.layer?.masksToBounds = true
    }

    func applyStoredFrame() {
        guard let screen = screenForStoredHandle() else { return }
        let size = CGFloat(appState.settings.floatingHandleSize)
        setContentSize(NSSize(width: size, height: size))
        applyCircleClip(size: size)
        let origin = FloatingHandleGeometry.origin(
            normalized: CGPoint(x: appState.settings.floatingHandleX, y: appState.settings.floatingHandleY),
            size: size,
            screen: screen.frame,
            menuBarHeight: screen.menuBarHeight
        )
        setFrameOrigin(origin)
        contentView?.layer?.contentsScale = screen.backingScaleFactor
    }

    func moveToCursor() {
        let size = frame.size.width
        let specs = NSScreen.screens.map {
            FloatingHandleGeometry.ScreenSpec(frame: $0.frame, menuBarHeight: $0.menuBarHeight)
        }
        let origin = FloatingHandleGeometry.clampedOrigin(
            cursor: NSEvent.mouseLocation,
            size: size,
            screens: specs
        )
        setFrameOrigin(origin)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) {
            contentView?.layer?.contentsScale = screen.backingScaleFactor
        }
    }

    func persistPosition() {
        guard let screen = screenContaining(frame.center) else { return }
        let normalized = FloatingHandleGeometry.normalized(
            origin: frame.origin,
            size: frame.width,
            screen: screen.frame,
            menuBarHeight: screen.menuBarHeight
        )
        appState.settings.floatingHandleX = normalized.x
        appState.settings.floatingHandleY = normalized.y
        appState.settings.floatingHandleDisplayID = Int(screen.displayID)
    }

    private func screenForStoredHandle() -> NSScreen? {
        let id = CGDirectDisplayID(appState.settings.floatingHandleDisplayID)
        if id != 0, let match = NSScreen.screens.first(where: { $0.displayID == id }) {
            return match
        }
        return screenContaining(NSEvent.mouseLocation)
            ?? NSScreen.screenWithMouse
            ?? NSScreen.screens.first
            ?? NSScreen.main
    }

    private func screenContaining(_ point: CGPoint) -> NSScreen? {
        if let hit = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            return hit
        }
        return NSScreen.screens.min {
            let a = $0.frame
            let b = $1.frame
            let da = hypot(point.x.clamped(to: a.minX...a.maxX) - point.x, point.y.clamped(to: a.minY...a.maxY) - point.y)
            let db = hypot(point.x.clamped(to: b.minX...b.maxX) - point.x, point.y.clamped(to: b.minY...b.maxY) - point.y)
            return da < db
        }
    }

    func handleClick() {
        guard appState.settings.useTuckBar else { return }
        if appState.navigation.isTuckBarPresented {
            tuckBarForceClose()
        } else {
            appState.menuBarManager.section(named: .hidden)?.show()
        }
    }

    func handleRightClick() {
        appState.openSettingsWindow(pane: .general)
    }

    private func tuckBarForceClose() {
        appState.tuckBar.forceClose()
    }
}

struct FloatingHandleView: View {
    @Environment(AppState.self) private var appState
    let panel: FloatingHandlePanel

    private var size: CGFloat { CGFloat(appState.settings.floatingHandleSize) }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.31, green: 0.55, blue: 0.98),
                            Color(red: 0.12, green: 0.32, blue: 0.86)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            Circle()
                .strokeBorder(.white.opacity(0.28), lineWidth: 0.5)
            glyph
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.18), radius: 0.5, y: 0.5)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .contentShape(Circle())
        .overlay {
            HandleClickDragView(panel: panel)
        }
        .help(String(localized: "Show hidden menu bar items"))
        .accessibilityLabel(String(localized: "Show hidden menu bar items"))
    }

    @ViewBuilder
    private var glyph: some View {
        switch appState.settings.floatingHandleIcon {
        case .chevron:
            Image(systemName: "chevron.down")
                .font(.system(size: size * 0.34, weight: .semibold))
        case .overflow:
            Image(systemName: "ellipsis")
                .font(.system(size: size * 0.38, weight: .bold))
        case .pocket:
            Image(systemName: "tray.fill")
                .font(.system(size: size * 0.36, weight: .medium))
        case .monogram:
            Text("T")
                .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
        }
    }
}

/// Distinguishes a click (toggle the bar) from a drag (reposition the button).
private struct HandleClickDragView: NSViewRepresentable {
    let panel: FloatingHandlePanel

    func makeNSView(context: Context) -> ClickOrDragView {
        ClickOrDragView(panel: panel)
    }

    func updateNSView(_ nsView: ClickOrDragView, context: Context) {
        nsView.panel = panel
    }
}

private final class ClickOrDragView: NSView {
    var panel: FloatingHandlePanel
    private var downLocation = CGPoint.zero
    private var dragging = false

    init(panel: FloatingHandlePanel) {
        self.panel = panel
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        downLocation = NSEvent.mouseLocation
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        let now = NSEvent.mouseLocation
        if hypot(now.x - downLocation.x, now.y - downLocation.y) > 4 {
            dragging = true
        }
        if dragging {
            panel.moveToCursor()
        }
    }

    override func mouseUp(with event: NSEvent) {
        if dragging {
            panel.persistPosition()
        } else if event.modifierFlags.contains(.control) {
            panel.handleRightClick()
        } else {
            panel.handleClick()
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        panel.handleRightClick()
    }
}
