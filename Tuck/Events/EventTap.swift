import AppKit
import OSLog

/// Receives system events from a location in the event stream.
@MainActor
final class EventTap {
    enum Location {
        case hidEventTap
        case sessionEventTap
        case annotatedSessionEventTap
        case pid(pid_t)

        var logString: String {
            switch self {
            case .hidEventTap: "HID event tap"
            case .sessionEventTap: "session event tap"
            case .annotatedSessionEventTap: "annotated session event tap"
            case .pid(let pid): "PID \(pid)"
            }
        }
    }

    /// Passed to the callback; can post events from the tap's location or toggle it.
    @MainActor
    struct Proxy {
        private let tap: EventTap
        private let pointer: CGEventTapProxy

        var label: String { tap.label }
        var isEnabled: Bool { tap.isEnabled }

        fileprivate init(tap: EventTap, pointer: CGEventTapProxy) {
            self.tap = tap
            self.pointer = pointer
        }

        func postEvent(_ event: CGEvent) {
            event.tapPostEvent(pointer)
        }

        func enable() { tap.enable() }
        func disable() { tap.disable() }
    }

    let label: String
    private let callback: @MainActor (Proxy, CGEventType, CGEvent) -> CGEvent?
    private var machPort: CFMachPort?
    private var source: CFRunLoopSource?

    var isEnabled: Bool {
        guard let machPort else { return false }
        return CGEvent.tapIsEnabled(tap: machPort)
    }

    init(
        label: String = #function,
        options: CGEventTapOptions,
        location: Location,
        place: CGEventTapPlacement,
        types: [CGEventType],
        callback: @escaping @MainActor (Proxy, CGEventType, CGEvent) -> CGEvent?
    ) {
        self.label = label
        self.callback = callback
        let mask: CGEventMask = types.reduce(into: 0) { $0 |= 1 << $1.rawValue }
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        let port: CFMachPort?
        switch location {
        case .pid(let pid):
            port = CGEvent.tapCreateForPid(pid: pid, place: place, options: options, eventsOfInterest: mask, callback: eventTapCallback, userInfo: userInfo)
        case .hidEventTap:
            port = CGEvent.tapCreate(tap: .cghidEventTap, place: place, options: options, eventsOfInterest: mask, callback: eventTapCallback, userInfo: userInfo)
        case .sessionEventTap:
            port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: place, options: options, eventsOfInterest: mask, callback: eventTapCallback, userInfo: userInfo)
        case .annotatedSessionEventTap:
            port = CGEvent.tapCreate(tap: .cgAnnotatedSessionEventTap, place: place, options: options, eventsOfInterest: mask, callback: eventTapCallback, userInfo: userInfo)
        }
        guard let port else {
            Logger.eventTap.error("Error creating mach port for event tap \"\(label)\"")
            return
        }
        guard let source = CFMachPortCreateRunLoopSource(nil, port, 0) else {
            Logger.eventTap.error("Error creating run loop source for event tap \"\(label)\"")
            return
        }
        machPort = port
        self.source = source
    }

    deinit {
        guard let machPort, let source else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: machPort, enable: false)
        CFMachPortInvalidate(machPort)
    }

    fileprivate func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> CGEvent? {
        if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
            enable()
            return nil
        }
        return callback(Proxy(tap: self, pointer: proxy), type, event)
    }

    func enable() {
        guard let machPort, let source else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: machPort, enable: true)
    }

    func enable(timeout: Duration, onTimeout: @escaping @MainActor () -> Void) {
        enable()
        Task { [weak self] in
            try? await Task.sleep(for: timeout)
            if self?.isEnabled == true {
                onTimeout()
            }
        }
    }

    func disable() {
        guard let machPort, let source else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: machPort, enable: false)
    }
}

/// The run loop source lives on the main run loop, so the callback always runs on the main thread.
private nonisolated func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
    nonisolated(unsafe) let event = event
    nonisolated(unsafe) var result: CGEvent?
    MainActor.assumeIsolated {
        result = tap.handle(proxy: proxy, type: type, event: event)
    }
    return result.map(Unmanaged.passUnretained)
}

nonisolated private extension Logger {
    static let eventTap = Logger(category: "EventTap")
}
