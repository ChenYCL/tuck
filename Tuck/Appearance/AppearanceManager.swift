import AppKit
import OSLog

/// Manages the menu bar's overlay-panel-based appearance (tint, shadow, border, shape).
///
/// Overlay panels are comparatively expensive to keep around (screen capture, AX polling),
/// so they only exist while the current configuration actually calls for one. When the
/// configuration needs nothing more than the plain system menu bar, `overlayPanels` is
/// empty and this manager is otherwise idle.
@MainActor
@Observable
final class AppearanceManager {
    @ObservationIgnored private unowned let appState: AppState

    /// The overlay panels currently on screen, one per `NSScreen`. Empty when the current
    /// (or previewed) configuration doesn't call for a visual overlay.
    private(set) var overlayPanels: [OverlayPanel] = []

    /// Set by the appearance editor while the user is actively dragging a color or gradient
    /// control, to preview the change live without committing it to `Settings`. `nil` means
    /// the committed `configuration` should be used.
    var previewConfiguration: PartialConfiguration?

    private(set) var isDraggingMenuBarItem = false

    /// The amount to inset the menu bar shape on screens with a notch.
    let menuBarInsetAmount: CGFloat = 5

    /// The committed menu bar appearance configuration.
    var configuration: AppearanceConfiguration { appState.settings.appearance }

    @ObservationIgnored private var observers: [Any] = []
    @ObservationIgnored private var pendingReconcile: Task<Void, Never>?
    @ObservationIgnored private var pendingScreenChange: Task<Void, Never>?
    @ObservationIgnored private var isSetUp = false

    init(appState: AppState) {
        self.appState = appState
    }

    func setup() {
        guard !isSetUp else { return }
        isSetUp = true
        configureObservers()
        reconcileOverlayPanels()
    }

    /// Forwards drag state to every overlay panel, fading their content out while a menu
    /// bar item is being dragged so the overlay doesn't visually interfere with the drag.
    func setIsDraggingMenuBarItem(_ isDragging: Bool) {
        guard isDraggingMenuBarItem != isDragging else { return }
        isDraggingMenuBarItem = isDragging
        for panel in overlayPanels {
            panel.setIsDraggingMenuBarItem(isDragging)
        }
    }

    private func configureObservers() {
        let center = NotificationCenter.default

        // Redraws happen immediately (cheap); creating or tearing down panels is
        // debounced, since configuration can change in rapid bursts while the user drags
        // a color or gradient control in the editor.
        observers.append(Observe.track { [weak self] in
            guard let self else { return }
            _ = appState.settings.appearance
            _ = previewConfiguration
            redrawAllPanels()
            scheduleReconcile()
        })

        // Redraw whenever the on-screen menu bar layout changes; the split shape's bounds
        // are derived from live item and application-menu frames.
        observers.append(Observe.track { [weak self] in
            guard let self else { return }
            _ = appState.itemStore.cache
            _ = appState.menuBarManager.sections
            redrawAllPanels()
        })

        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleScreenParametersChanged() }
        })

        // `effectiveAppearance` isn't `@Observable`, but it is KVO-compliant; a dynamic
        // configuration's `current` partial depends on it.
        observers.append(NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.redrawAllPanels() }
        })
    }

    private func redrawAllPanels() {
        for panel in overlayPanels {
            panel.setNeedsDisplay()
        }
    }

    private func scheduleReconcile() {
        pendingReconcile?.cancel()
        pendingReconcile = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self?.reconcileOverlayPanels()
        }
    }

    private func scheduleScreenParametersChanged() {
        pendingScreenChange?.cancel()
        pendingScreenChange = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self?.rebuildOverlayPanelsForScreenChange()
        }
    }

    /// Whether the current (or previewed) configuration calls for an overlay panel at all.
    private var needsOverlayPanels: Bool {
        let current = previewConfiguration ?? configuration.current
        return current.hasShadow || current.hasBorder || configuration.shapeKind != .none || current.tintKind != .none
    }

    private func reconcileOverlayPanels() {
        if needsOverlayPanels {
            guard overlayPanels.isEmpty else { return }
            Logger.appearanceManager.debug("Creating overlay panels")
            createOverlayPanels()
        } else {
            closeOverlayPanels()
        }
    }

    /// Always rebuilds from scratch, so the panel set exactly matches `NSScreen.screens`.
    private func rebuildOverlayPanelsForScreenChange() {
        closeOverlayPanels()
        guard needsOverlayPanels else { return }
        createOverlayPanels()
    }

    private func createOverlayPanels() {
        overlayPanels = NSScreen.screens.map { screen in
            let panel = OverlayPanel(appState: appState, owningScreen: screen)
            panel.show()
            return panel
        }
    }

    private func closeOverlayPanels() {
        guard !overlayPanels.isEmpty else { return }
        Logger.appearanceManager.debug("Closing overlay panels")
        for panel in overlayPanels {
            panel.close()
        }
        overlayPanels = []
    }
}

nonisolated private extension Logger {
    static let appearanceManager = Logger(category: "AppearanceManager")
}
