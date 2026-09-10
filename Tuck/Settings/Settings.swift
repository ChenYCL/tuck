import Foundation
import Observation

@MainActor
@Observable
final class Settings {
    @ObservationIgnored private let defaults = UserDefaults.standard

    var showTuckIcon: Bool { didSet { defaults.set(showTuckIcon, for: .showTuckIcon) } }
    var tuckIcon: ControlIcon { didSet { defaults.setEncoded(tuckIcon, for: .tuckIcon) } }
    var customIconIsTemplate: Bool { didSet { defaults.set(customIconIsTemplate, for: .customIconIsTemplate) } }
    var useTuckBar: Bool { didSet { defaults.set(useTuckBar, for: .useTuckBar) } }
    var tuckBarLocation: TuckBarLocation { didSet { defaults.set(tuckBarLocation, for: .tuckBarLocation) } }
    var tuckBarAlwaysVisible: Bool { didSet { defaults.set(tuckBarAlwaysVisible, for: .tuckBarAlwaysVisible) } }
    var showFloatingHandle: Bool { didSet { defaults.set(showFloatingHandle, for: .showFloatingHandle) } }
    var floatingHandleSize: Double { didSet { defaults.set(floatingHandleSize, for: .floatingHandleSize) } }
    var floatingHandleIcon: FloatingHandleIcon { didSet { defaults.set(floatingHandleIcon, for: .floatingHandleIcon) } }
    var floatingHandleX: Double { didSet { defaults.set(floatingHandleX, for: .floatingHandleX) } }
    var floatingHandleY: Double { didSet { defaults.set(floatingHandleY, for: .floatingHandleY) } }
    var showOnClick: Bool { didSet { defaults.set(showOnClick, for: .showOnClick) } }
    var showOnHover: Bool { didSet { defaults.set(showOnHover, for: .showOnHover) } }
    var showOnScroll: Bool { didSet { defaults.set(showOnScroll, for: .showOnScroll) } }
    var autoRehide: Bool { didSet { defaults.set(autoRehide, for: .autoRehide) } }
    var rehideStrategy: RehideStrategy { didSet { defaults.set(rehideStrategy, for: .rehideStrategy) } }
    var rehideInterval: TimeInterval { didSet { defaults.set(rehideInterval, for: .rehideInterval) } }
    var itemSpacingOffset: Int { didSet { defaults.set(itemSpacingOffset, for: .itemSpacingOffset) } }
    var hideApplicationMenus: Bool { didSet { defaults.set(hideApplicationMenus, for: .hideApplicationMenus) } }
    var showSectionDividers: Bool { didSet { defaults.set(showSectionDividers, for: .showSectionDividers) } }
    var enableAlwaysHiddenSection: Bool { didSet { defaults.set(enableAlwaysHiddenSection, for: .enableAlwaysHiddenSection) } }
    var canToggleAlwaysHiddenSection: Bool { didSet { defaults.set(canToggleAlwaysHiddenSection, for: .canToggleAlwaysHiddenSection) } }
    var showOnHoverDelay: TimeInterval { didSet { defaults.set(showOnHoverDelay, for: .showOnHoverDelay) } }
    var tempShowInterval: TimeInterval { didSet { defaults.set(tempShowInterval, for: .tempShowInterval) } }
    var showAllSectionsOnUserDrag: Bool { didSet { defaults.set(showAllSectionsOnUserDrag, for: .showAllSectionsOnUserDrag) } }
    var showContextMenuOnRightClick: Bool { didSet { defaults.set(showContextMenuOnRightClick, for: .showContextMenuOnRightClick) } }
    var hotkeys: [HotkeyAction: KeyCombination] { didSet { defaults.setEncoded(hotkeys, for: .hotkeys) } }
    var appearance: AppearanceConfiguration { didSet { defaults.setEncoded(appearance, for: .appearanceConfiguration) } }
    var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, for: .hasCompletedOnboarding) } }

    init() {
        showTuckIcon = defaults.bool(for: .showTuckIcon, default: true)
        tuckIcon = defaults.decoded(for: .tuckIcon, default: .dot)
        customIconIsTemplate = defaults.bool(for: .customIconIsTemplate, default: false)
        useTuckBar = defaults.bool(for: .useTuckBar, default: true)
        tuckBarLocation = defaults.rawValue(for: .tuckBarLocation, default: .below)
        tuckBarAlwaysVisible = defaults.bool(for: .tuckBarAlwaysVisible, default: false)
        showFloatingHandle = defaults.bool(for: .showFloatingHandle, default: true)
        floatingHandleSize = defaults.double(for: .floatingHandleSize, default: 48)
        floatingHandleIcon = defaults.rawValue(for: .floatingHandleIcon, default: .chevron)
        floatingHandleX = defaults.double(for: .floatingHandleX, default: 1)
        floatingHandleY = defaults.double(for: .floatingHandleY, default: 0.62)
        showOnClick = defaults.bool(for: .showOnClick, default: true)
        showOnHover = defaults.bool(for: .showOnHover, default: false)
        showOnScroll = defaults.bool(for: .showOnScroll, default: true)
        autoRehide = defaults.bool(for: .autoRehide, default: true)
        rehideStrategy = defaults.rawValue(for: .rehideStrategy, default: .smart)
        rehideInterval = defaults.double(for: .rehideInterval, default: 15)
        itemSpacingOffset = defaults.integer(for: .itemSpacingOffset, default: 0)
        hideApplicationMenus = defaults.bool(for: .hideApplicationMenus, default: true)
        showSectionDividers = defaults.bool(for: .showSectionDividers, default: false)
        enableAlwaysHiddenSection = defaults.bool(for: .enableAlwaysHiddenSection, default: false)
        canToggleAlwaysHiddenSection = defaults.bool(for: .canToggleAlwaysHiddenSection, default: true)
        showOnHoverDelay = defaults.double(for: .showOnHoverDelay, default: 0.2)
        tempShowInterval = defaults.double(for: .tempShowInterval, default: 15)
        showAllSectionsOnUserDrag = defaults.bool(for: .showAllSectionsOnUserDrag, default: true)
        showContextMenuOnRightClick = defaults.bool(for: .showContextMenuOnRightClick, default: true)
        hotkeys = defaults.decoded(for: .hotkeys, default: [:])
        appearance = defaults.decoded(for: .appearanceConfiguration, default: .default)
        hasCompletedOnboarding = defaults.bool(for: .hasCompletedOnboarding, default: false)
    }
}
