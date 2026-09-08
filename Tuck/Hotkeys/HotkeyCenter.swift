import AppKit
import Carbon.HIToolbox
import OSLog

/// Registers global hotkeys through Carbon and dispatches them to `HotkeyAction`s.
@MainActor
final class HotkeyCenter {
    private struct Registration {
        let id: UInt32
        let ref: EventHotKeyRef
    }

    private nonisolated static let signature: OSType = 0x5475636B // "Tuck"

    private unowned let appState: AppState
    private var handlerRef: EventHandlerRef?
    private var registrations: [HotkeyAction: Registration] = [:]
    private var nextID: UInt32 = 1
    private var suspended: Set<HotkeyAction> = []
    private var isMenuTracking = false
    private var observers: [Any] = []

    init(appState: AppState) {
        self.appState = appState
    }

    func setup() {
        installHandlerIfNeeded()
        observers.append(Observe.track { [weak self] in
            guard let self else { return }
            _ = appState.settings.hotkeys
            _ = appState.settings.enableAlwaysHiddenSection
            _ = appState.settings.showTuckIcon
            registerAll()
        })
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isMenuTracking = true
                self?.registerAll()
            }
        })
        observers.append(center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isMenuTracking = false
                self?.registerAll()
            }
        })
    }

    /// Temporarily unregisters the hotkey for an action (e.g. while recording a new one).
    func suspend(_ action: HotkeyAction) {
        suspended.insert(action)
        registerAll()
    }

    func resume(_ action: HotkeyAction) {
        suspended.remove(action)
        registerAll()
    }

    private func isEnabled(_ action: HotkeyAction) -> Bool {
        let manager = appState.menuBarManager
        switch action {
        case .toggleHiddenSection: return manager.section(named: .hidden)?.isEnabled ?? false
        case .toggleAlwaysHiddenSection: return manager.section(named: .alwaysHidden)?.isEnabled ?? false
        default: return true
        }
    }

    private func registerAll() {
        for action in HotkeyAction.allCases {
            unregister(action)
        }
        guard !isMenuTracking else { return }
        for (action, combination) in appState.settings.hotkeys where !suspended.contains(action) && isEnabled(action) {
            register(action, combination: combination)
        }
    }

    private func register(_ action: HotkeyAction, combination: KeyCombination) {
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            UInt32(combination.key.rawValue),
            UInt32(combination.modifiers.carbonFlags),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            Logger.hotkeys.error("Failed to register hotkey for \(action.rawValue): \(status)")
            return
        }
        registrations[action] = Registration(id: id, ref: ref)
    }

    private func unregister(_ action: HotkeyAction) {
        guard let registration = registrations.removeValue(forKey: action) else { return }
        UnregisterEventHotKey(registration.ref)
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
        ]
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            Self.handler,
            types.count,
            &types,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        if status != noErr {
            Logger.hotkeys.error("Failed to install hotkey handler: \(status)")
        }
    }

    private nonisolated static let handler: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr, hotKeyID.signature == signature else { return OSStatus(eventNotHandledErr) }
        let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
        MainActor.assumeIsolated {
            center.handle(id: hotKeyID.id)
        }
        return noErr
    }

    private func handle(id: UInt32) {
        guard let action = registrations.first(where: { $0.value.id == id })?.key else { return }
        action.perform(appState: appState)
    }
}

nonisolated private extension Logger {
    static let hotkeys = Logger(category: "HotkeyCenter")
}
