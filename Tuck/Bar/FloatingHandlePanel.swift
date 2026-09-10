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
        guard let screen = NSScreen.screenWithActiveMenuBar ?? NSScreen.screens.first ?? NSScreen.main else { return }
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
    }

    func moveToCursor() {
        guard let screen = screen ?? NSScreen.main else { return }
        let size = frame.size
        var origin = CGPoint(
            x: NSEvent.mouseLocation.x - size.width / 2,
            y: NSEvent.mouseLocation.y - size.height / 2
        )
        let bounds = FloatingHandleGeometry.movableBounds(
            size: size.width,
            screen: screen.frame,
            menuBarHeight: screen.menuBarHeight
        )
        origin.x = origin.x.clamped(to: bounds.minX...bounds.maxX)
        origin.y = origin.y.clamped(to: bounds.minY...bounds.maxY)
        setFrameOrigin(origin)
    }

    func persistPosition() {
        guard let screen = screen ?? NSScreen.main else { return }
        let normalized = FloatingHandleGeometry.normalized(
            origin: frame.origin,
            size: frame.width,
            screen: screen.frame,
            menuBarHeight: screen.menuBarHeight
        )
        appState.settings.floatingHandleX = normalized.x
        appState.settings.floatingHandleY = normalized.y
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
