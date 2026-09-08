import AppKit
import SwiftUI

/// Anchors a popover-hosted `AppearancePane` beneath the menu bar, for quick in-place
/// appearance editing from the control item's right-click menu.
@MainActor
final class AppearanceEditorPanel {
    private unowned let appState: AppState
    private let anchor: NSPanel
    private let popover: NSPopover
    private var monitor: EventMonitor?

    init(appState: AppState) {
        self.appState = appState

        anchor = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        anchor.isFloatingPanel = true
        anchor.level = .popUpMenu
        anchor.backgroundColor = .clear
        anchor.hasShadow = false
        anchor.isReleasedWhenClosed = false
        anchor.ignoresMouseEvents = true
        anchor.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .moveToActiveSpace]
        anchor.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))

        popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.contentSize = NSSize(width: 520, height: 560)
        popover.contentViewController = NSHostingController(rootView: AppearancePane().environment(appState))
    }

    func show() {
        guard let screen = NSScreen.main, let contentView = anchor.contentView else { return }

        let origin = NSPoint(x: screen.frame.midX - 0.5, y: screen.frame.maxY - screen.menuBarHeight)
        anchor.setFrame(NSRect(origin: origin, size: NSSize(width: 1, height: 1)), display: false)
        anchor.orderFront(nil)

        popover.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)

        let monitor = EventMonitor(mask: .leftMouseDown, scope: .universal) { [weak self] event in
            guard let self else { return event }
            let popoverWindow = self.popover.contentViewController?.view.window
            if event.window !== popoverWindow {
                self.close()
            }
            return event
        }
        monitor.start()
        self.monitor = monitor
    }

    func close() {
        popover.close()
        anchor.orderOut(nil)
        monitor?.stop()
        monitor = nil
        NSColorPanel.shared.close()
    }
}
