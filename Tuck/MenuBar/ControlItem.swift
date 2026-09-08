import AppKit
import OSLog

@MainActor
final class ControlItem {
    enum Identifier: String, CaseIterable {
        case tuckIcon = "TuckIcon"
        case hidden = "TuckHidden"
        case alwaysHidden = "TuckAlwaysHidden"
    }

    enum HidingState {
        case hideItems
        case showItems
    }

    enum Lengths {
        static let standard: CGFloat = NSStatusItem.variableLength
        static let expanded: CGFloat = 10_000
    }

    let identifier: Identifier
    private unowned let appState: AppState
    private let statusItem: NSStatusItem
    private let constraint: NSLayoutConstraint?
    private var observers: [Any] = []

    /// The section this control item belongs to; assigned by `MenuBarSection`.
    weak var section: MenuBarSection?

    var state: HidingState = .hideItems {
        didSet {
            guard state != oldValue else { return }
            updateAppearance()
            applyLength()
        }
    }

    private(set) var isVisible = true {
        didSet {
            guard isVisible != oldValue else { return }
            applyLength()
        }
    }

    /// The frame of the control item's window, updated only while on a screen.
    private(set) var windowFrame: CGRect?

    var window: NSWindow? { statusItem.button?.window }

    var windowID: CGWindowID? {
        window.map { CGWindowID($0.windowNumber) }
    }

    var isSectionDivider: Bool { identifier != .tuckIcon }

    var isAddedToMenuBar: Bool { statusItem.isVisible }

    init(identifier: Identifier, appState: AppState) {
        let autosaveName = identifier.rawValue
        if StatusItemDefaults[preferredPosition: autosaveName] == nil {
            switch identifier {
            case .tuckIcon: StatusItemDefaults[preferredPosition: autosaveName] = 0
            case .hidden: StatusItemDefaults[preferredPosition: autosaveName] = 1
            case .alwaysHidden: break
            }
        }

        self.identifier = identifier
        self.appState = appState
        self.statusItem = NSStatusBar.system.statusItem(withLength: 0)
        statusItem.autosaveName = autosaveName

        // AppKit enforces a minimum non-zero width on status items. Grabbing the
        // constraint lets the divider collapse to zero width while remaining in
        // the menu bar as a section delimiter.
        if
            let button = statusItem.button,
            let constraints = button.window?.contentView?.constraintsAffectingLayout(for: .horizontal)
        {
            constraint = constraints.first { $0.secondItem === button.superview }
        } else {
            constraint = nil
        }

        if let button = statusItem.button {
            // Menu bar item windows belong to Control Center on macOS 26; the accessibility
            // identifier is how Tuck recognizes its own items without screen recording.
            button.setAccessibilityIdentifier(autosaveName)
            button.setAccessibilityLabel(identifier == .tuckIcon ? Constants.appName : "\(Constants.appName) \(identifier.rawValue)")
            button.target = self
            button.action = #selector(performAction)
            button.sendAction(on: appState.settings.useTuckBar ? [.leftMouseDown, .rightMouseUp] : [.leftMouseUp, .rightMouseUp])
        }

        configureObservers()
    }

    deinit {
        // Removing the status item deletes the preferred position. Cache and restore it.
        let autosaveName = statusItem.autosaveName as String
        let cached = StatusItemDefaults[preferredPosition: autosaveName]
        NSStatusBar.system.removeStatusItem(statusItem)
        StatusItemDefaults[preferredPosition: autosaveName] = cached
    }

    /// Called by `MenuBarSection` once the section relationship is established.
    func activate() {
        updateAppearance()
        applyLength()
    }

    private func configureObservers() {
        if let window {
            observers.append(window.observe(\.frame, options: [.initial, .new]) { [weak self] window, _ in
                MainActor.assumeIsolated {
                    guard let self, let screen = window.screen, screen.frame.intersects(window.frame) else { return }
                    self.windowFrame = window.frame
                }
            })
        }

        let settings = appState.settings
        observers.append(Observe.track { [weak self] in
            guard let self else { return }
            let show = settings.showTuckIcon
            guard identifier == .tuckIcon else { return }
            if show { addToMenuBar() } else { removeFromMenuBar() }
        })
        observers.append(Observe.track { [weak self] in
            guard let self else { return }
            _ = settings.tuckIcon
            _ = settings.customIconIsTemplate
            _ = settings.showSectionDividers
            updateAppearance()
        })
        observers.append(Observe.track { [weak self] in
            guard let self, let button = statusItem.button else { return }
            button.sendAction(on: settings.useTuckBar ? [.leftMouseDown, .rightMouseUp] : [.leftMouseUp, .rightMouseUp])
        })
        observers.append(Observe.track { [weak self] in
            guard let self else { return }
            let enable = settings.enableAlwaysHiddenSection
            guard identifier == .alwaysHidden else { return }
            if enable { addToMenuBar() } else { removeFromMenuBar() }
        })
    }

    private func applyLength() {
        guard let section else { return }
        if isVisible {
            statusItem.length = switch section.name {
            case .visible: Lengths.standard
            case .hidden, .alwaysHidden:
                switch state {
                case .hideItems: Lengths.expanded
                case .showItems: Lengths.standard
                }
            }
            constraint?.isActive = true
            window?.alphaValue = 1
        } else {
            statusItem.length = 0
            constraint?.isActive = false
            if let window {
                // macOS 26 renders even a 1 pt item as a hairline. Collapse the window to
                // zero width; it still exists as a section delimiter.
                var size = window.frame.size
                size.width = 0
                window.setContentSize(size)
                window.alphaValue = 0
            }
        }
    }

    private func updateAppearance() {
        guard let section, let button = statusItem.button else { return }
        let settings = appState.settings
        switch section.name {
        case .visible:
            isVisible = true
            button.cell?.isEnabled = true
            button.image = settings.tuckIcon.image(state: state, isTemplate: settings.customIconIsTemplate)
        case .hidden, .alwaysHidden:
            switch state {
            case .hideItems:
                isVisible = true
                // Prevent the cell from highlighting while expanded.
                button.cell?.isEnabled = false
                button.isHighlighted = false
                button.image = nil
            case .showItems:
                isVisible = settings.showSectionDividers
                button.cell?.isEnabled = true
                button.image = ControlIcon.dividerImage(for: identifier)
            }
        }
    }

    @objc private func performAction() {
        guard let event = NSApp.currentEvent, !event.isSynthesizedByTuck else { return }
        switch event.type {
        case .leftMouseDown, .leftMouseUp:
            let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .control {
                statusItem.showMenu(makeMenu())
            } else if flags == .option, appState.settings.canToggleAlwaysHiddenSection {
                appState.menuBarManager.section(named: .alwaysHidden)?.toggle()
            } else {
                section?.toggle()
            }
        case .rightMouseUp:
            statusItem.showMenu(makeMenu())
        default:
            break
        }
    }

    func makeMenu() -> NSMenu {
        appState.menuBarManager.makeContextMenu()
    }

    func addToMenuBar() {
        guard !isAddedToMenuBar else { return }
        statusItem.isVisible = true
    }

    func removeFromMenuBar() {
        guard isAddedToMenuBar else { return }
        // Setting `isVisible = false` deletes the preferred position. Cache and restore it.
        let autosaveName = statusItem.autosaveName as String
        let cached = StatusItemDefaults[preferredPosition: autosaveName]
        statusItem.isVisible = false
        StatusItemDefaults[preferredPosition: autosaveName] = cached
    }

    /// Re-adds the status item directly to the right of `other` using AppKit's own
    /// preferred-position bookkeeping (positions grow leftwards from the trailing edge).
    func reposition(rightOf other: ControlItem) {
        guard let otherPosition = StatusItemDefaults[preferredPosition: other.identifier.rawValue] else { return }
        let wasVisible = statusItem.isVisible
        statusItem.isVisible = false
        StatusItemDefaults[preferredPosition: identifier.rawValue] = max(otherPosition - 1, 0)
        if wasVisible {
            statusItem.isVisible = true
        }
    }

    /// Forces the divider to be visible; used when the user ⌘-drags items.
    func showDivider() {
        guard isSectionDivider, !isVisible else { return }
        isVisible = true
    }
}
