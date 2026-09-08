import AppKit

/// Wraps AppKit global/local event monitors with explicit start/stop.
@MainActor
final class EventMonitor {
    enum Scope {
        case global
        case local
        case universal
    }

    private let mask: NSEvent.EventTypeMask
    private let scope: Scope
    private let handler: @MainActor (NSEvent) -> NSEvent?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    var isRunning: Bool { globalMonitor != nil || localMonitor != nil }

    init(mask: NSEvent.EventTypeMask, scope: Scope, handler: @escaping @MainActor (NSEvent) -> NSEvent?) {
        self.mask = mask
        self.scope = scope
        self.handler = handler
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }

    func start() {
        guard !isRunning else { return }
        let handler = handler
        if scope != .local {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { event in
                MainActor.assumeIsolated { _ = handler(event) }
            }
        }
        if scope != .global {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
                nonisolated(unsafe) let event = event
                nonisolated(unsafe) var result: NSEvent?
                MainActor.assumeIsolated { result = handler(event) }
                return result
            }
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }
}
