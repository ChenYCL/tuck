import AppKit
import OSLog

/// Moves, clicks, and temporarily shows menu bar items by posting synthesized events
/// through the item's source process.
@MainActor
final class ItemMover {
    enum MoveDestination {
        case leftOfItem(MenuBarItem)
        case rightOfItem(MenuBarItem)

        var targetItem: MenuBarItem {
            switch self {
            case .leftOfItem(let item), .rightOfItem(let item): item
            }
        }
    }

    enum EventError: LocalizedError {
        case cannotComplete
        case invalidEventSource
        case missingMouseLocation
        case eventCreationFailure(MenuBarItem)
        case eventOperationTimeout(MenuBarItem)
        case itemNotMovable(MenuBarItem)
        case itemResponseTimeout(MenuBarItem)
        case missingItemBounds(MenuBarItem)

        var errorDescription: String? {
            switch self {
            case .cannotComplete: String(localized: "Operation could not be completed")
            case .invalidEventSource: String(localized: "Invalid event source")
            case .missingMouseLocation: String(localized: "Missing mouse location")
            case .eventCreationFailure(let item): String(localized: "Could not create event for \"\(item.displayName)\"")
            case .eventOperationTimeout(let item): String(localized: "Event operation timed out for \"\(item.displayName)\"")
            case .itemNotMovable(let item): String(localized: "\"\(item.displayName)\" is not movable")
            case .itemResponseTimeout(let item): String(localized: "\"\(item.displayName)\" took too long to respond")
            case .missingItemBounds(let item): String(localized: "Missing bounds for \"\(item.displayName)\"")
            }
        }

        var recoverySuggestion: String? {
            if case .itemNotMovable = self { return nil }
            return String(localized: "Please try again. If the error persists, please file a bug report.")
        }
    }

    private final class TempShownContext {
        let info: MenuBarItemInfo
        let returnDestination: MoveDestination
        var shownInterfaceWindow: WindowInfo?
        var rehideAttempts = 0

        init(info: MenuBarItemInfo, returnDestination: MoveDestination) {
            self.info = info
            self.returnDestination = returnDestination
        }

        var isShowingInterface: Bool {
            guard let window = shownInterfaceWindow, let current = WindowInfo(windowID: window.windowID) else {
                return false
            }
            let popUp = Int(CGWindowLevelForKey(.popUpMenuWindow))
            if
                current.layer != popUp,
                current.layer != popUp - 1,
                current.layer != Int(CGWindowLevelForKey(.statusWindow)),
                current.layer != Int(CGWindowLevelForKey(.mainMenuWindow)),
                let app = current.owningApplication
            {
                return app.isActive && current.isOnScreen
            }
            return current.isOnScreen
        }
    }

    private unowned let appState: AppState
    private var mouseMonitor: EventMonitor?
    private var lastMouseMoveDate: Date?
    private var lastScrollDate: Date?
    private var lastMoveOperationDate: Date?
    private var itemMoveCount = 0
    private var isPostingEvents = false
    private var moveTimeouts: [MenuBarItemInfo: Duration] = [:]
    private var tempShownContexts: [TempShownContext] = []
    private var rehideTimer: Timer?

    var isMovingItem: Bool { itemMoveCount > 0 }

    var itemHasRecentlyMoved: Bool {
        lastMoveOperationDate.map { Date.now.timeIntervalSince($0) <= 1 } ?? false
    }

    var mouseHasRecentlyMoved: Bool {
        lastMouseMoveDate.map { Date.now.timeIntervalSince($0) <= 1 } ?? false
    }

    var isMouseButtonDown: Bool { NSEvent.pressedMouseButtons != 0 }

    init(appState: AppState) {
        self.appState = appState
    }

    func setup() {
        let monitor = EventMonitor(mask: [.mouseMoved, .leftMouseDragged, .scrollWheel], scope: .universal) { [weak self] event in
            if event.type == .scrollWheel {
                self?.lastScrollDate = .now
            } else {
                self?.lastMouseMoveDate = .now
            }
            return event
        }
        monitor.start()
        mouseMonitor = monitor
    }

    // MARK: - Waiting

    func waitForItemsToStopMoving(timeout: Duration) async throws {
        try await withTimeout(timeout) { [weak self] in
            while let self, isMovingItem {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    private func hasUserPausedInput(for duration: TimeInterval) -> Bool {
        let now = Date.now
        let moved = lastMouseMoveDate.map { now.timeIntervalSince($0) < duration } ?? false
        let scrolled = lastScrollDate.map { now.timeIntervalSince($0) < duration } ?? false
        return NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty && !moved && !scrolled && !isMouseButtonDown
    }

    private func waitForUserToPauseInput() async throws {
        while !hasUserPausedInput(for: 0.05) {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(250))
        }
    }

    private func waitForMoveOperationBuffer() async throws {
        guard let lastMoveOperationDate else { return }
        let elapsed = Date.now.timeIntervalSince(lastMoveOperationDate)
        let buffer = max(0.025 - elapsed, 0)
        if buffer > 0 {
            try await Task.sleep(for: .seconds(buffer))
        }
    }

    private func eventSleep(for duration: Duration = .milliseconds(25)) async {
        try? await Task.sleep(for: duration)
    }

    private func acquireEventLock() async throws {
        while isPostingEvents {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(10))
        }
        isPostingEvents = true
    }

    private func releaseEventLock() {
        isPostingEvents = false
    }

    // MARK: - Geometry

    private func currentBounds(for item: MenuBarItem) throws -> CGRect {
        guard let bounds = Bridging.windowFrame(for: item.windowID) else {
            throw EventError.missingItemBounds(item)
        }
        return bounds
    }

    private func targetPoints(forMoving item: MenuBarItem, to destination: MoveDestination) throws -> (start: CGPoint, end: CGPoint) {
        let itemBounds = try currentBounds(for: item)
        let targetBounds = try currentBounds(for: destination.targetItem)
        switch destination {
        case .leftOfItem:
            var start = CGPoint(x: targetBounds.minX, y: targetBounds.minY)
            var end = start
            if itemBounds.maxX <= targetBounds.minX {
                end.x -= itemBounds.width
            } else {
                start.x -= 1
            }
            return (start, end)
        case .rightOfItem:
            var start = CGPoint(x: targetBounds.maxX, y: targetBounds.minY)
            var end = start
            if itemBounds.minX <= targetBounds.maxX {
                end.x -= itemBounds.width
            } else {
                start.x += 1
            }
            return (start, end)
        }
    }

    func itemHasCorrectPosition(item: MenuBarItem, for destination: MoveDestination) throws -> Bool {
        let itemBounds = try currentBounds(for: item)
        let targetBounds = try currentBounds(for: destination.targetItem)
        return switch destination {
        case .leftOfItem: itemBounds.maxX == targetBounds.minX
        case .rightOfItem: itemBounds.minX == targetBounds.maxX
        }
    }

    // MARK: - Event plumbing

    private func eventSource(_ stateID: CGEventSourceStateID = .hidSystemState) throws -> CGEventSource {
        guard let source = CGEventSource(stateID: stateID) else { throw EventError.invalidEventSource }
        return source
    }

    private func permitLocalEvents() throws {
        let source = try eventSource(.combinedSessionState)
        for state in [CGEventSuppressionState.eventSuppressionStateRemoteMouseDrag, .eventSuppressionStateSuppressionInterval] {
            source.setLocalEventsFilterDuringSuppressionState(.permitAllEvents, state: state)
        }
        source.localEventsSuppressionInterval = 0
    }

    private func mouseLocation() throws -> CGPoint {
        guard let location = MouseCursor.locationCoreGraphics else { throw EventError.missingMouseLocation }
        return location
    }

    /// Posts `event` to the item's process and waits until it is observed at the session tap.
    private func postEventWithBarrier(_ event: CGEvent, to item: MenuBarItem, timeout: Duration, repeating count: Int = 1) async throws {
        MouseCursor.hide()
        defer { MouseCursor.show() }

        guard let entryEvent = CGEvent.uniqueNullEvent(), let exitEvent = CGEvent.uniqueNullEvent() else {
            throw EventError.eventCreationFailure(item)
        }
        let pid = item.eventPID
        event.setTargetPID(pid)
        let firstLocation = EventTap.Location.pid(pid)
        let secondLocation = EventTap.Location.sessionEventTap

        let taps = TapBox()
        do {
            try await withTimeout(timeout * count) {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    let resumer = Resumer(continuation)
                    var remaining = count
                    let tap1 = EventTap(label: "barrier-1", options: .defaultTap, location: firstLocation, place: .headInsertEventTap, types: [.null]) { proxy, _, rEvent in
                        if rEvent.matches(entryEvent, byIntegerFields: [.eventSourceUserData]) {
                            remaining -= 1
                            event.post(to: secondLocation)
                            return nil
                        }
                        if rEvent.matches(exitEvent, byIntegerFields: [.eventSourceUserData]) {
                            proxy.disable()
                            resumer.resume()
                            return nil
                        }
                        return rEvent
                    }
                    let tap2 = EventTap(label: "barrier-2", options: .listenOnly, location: secondLocation, place: .tailAppendEventTap, types: [event.type]) { proxy, _, rEvent in
                        guard rEvent.matches(event, byIntegerFields: CGEventField.menuBarItemEventFields) else { return rEvent }
                        if remaining <= 0 {
                            proxy.disable()
                            exitEvent.post(to: firstLocation)
                        } else {
                            entryEvent.post(to: firstLocation)
                        }
                        rEvent.setTargetPID(pid)
                        return rEvent
                    }
                    taps.taps = [tap1, tap2]
                    tap1.enable()
                    tap2.enable()
                    entryEvent.post(to: firstLocation)
                }
            }
        } catch is TaskTimeoutError {
            taps.disableAll()
            throw EventError.eventOperationTimeout(item)
        } catch {
            taps.disableAll()
            throw EventError.cannotComplete
        }
        taps.disableAll()
    }

    /// Relays `event` between the item's process and the session tap so the item receives
    /// and responds to it as part of a move operation.
    private func scrombleEvent(_ event: CGEvent, item: MenuBarItem, timeout: Duration, repeating count: Int = 1) async throws {
        MouseCursor.hide()
        defer { MouseCursor.show() }

        guard let entryEvent = CGEvent.uniqueNullEvent(), let exitEvent = CGEvent.uniqueNullEvent() else {
            throw EventError.eventCreationFailure(item)
        }
        let pid = item.eventPID
        event.setTargetPID(pid)
        let firstLocation = EventTap.Location.pid(pid)
        let secondLocation = EventTap.Location.sessionEventTap

        let taps = TapBox()
        do {
            try await withTimeout(timeout * count) {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    let resumer = Resumer(continuation)
                    var remaining = count
                    let tap1 = EventTap(label: "scromble-1", options: .defaultTap, location: firstLocation, place: .headInsertEventTap, types: [.null]) { proxy, _, rEvent in
                        if rEvent.matches(entryEvent, byIntegerFields: [.eventSourceUserData]) {
                            remaining -= 1
                            event.post(to: secondLocation)
                            return nil
                        }
                        if rEvent.matches(exitEvent, byIntegerFields: [.eventSourceUserData]) {
                            proxy.disable()
                            resumer.resume()
                            return nil
                        }
                        return rEvent
                    }
                    let tap2 = EventTap(label: "scromble-2", options: .listenOnly, location: secondLocation, place: .tailAppendEventTap, types: [event.type]) { proxy, _, rEvent in
                        guard rEvent.matches(event, byIntegerFields: CGEventField.menuBarItemEventFields) else { return rEvent }
                        if remaining <= 0 {
                            proxy.disable()
                        }
                        event.post(to: firstLocation)
                        rEvent.setTargetPID(pid)
                        return rEvent
                    }
                    let tap3 = EventTap(label: "scromble-3", options: .listenOnly, location: firstLocation, place: .headInsertEventTap, types: [event.type]) { proxy, _, rEvent in
                        guard rEvent.matches(event, byIntegerFields: CGEventField.menuBarItemEventFields) else { return rEvent }
                        if remaining <= 0 {
                            proxy.disable()
                            exitEvent.post(to: firstLocation)
                        } else {
                            entryEvent.post(to: firstLocation)
                        }
                        rEvent.setTargetPID(pid)
                        return rEvent
                    }
                    taps.taps = [tap1, tap2, tap3]
                    tap1.enable()
                    tap2.enable()
                    tap3.enable()
                    entryEvent.post(to: firstLocation)
                }
            }
        } catch is TaskTimeoutError {
            taps.disableAll()
            throw EventError.eventOperationTimeout(item)
        } catch {
            taps.disableAll()
            throw EventError.cannotComplete
        }
        taps.disableAll()
    }

    // MARK: - Moving

    private func defaultMoveTimeout(for item: MenuBarItem) -> Duration {
        item.isBentoBox ? .milliseconds(100) : .milliseconds(50)
    }

    private func moveTimeout(for item: MenuBarItem) -> Duration {
        moveTimeouts[item.info] ?? defaultMoveTimeout(for: item)
    }

    private func updateMoveTimeout(_ timeout: Duration, for item: MenuBarItem) {
        let average = (timeout + moveTimeout(for: item)) / 2
        moveTimeouts[item.info] = min(max(average, .milliseconds(25)), .milliseconds(150))
    }

    private func waitForMoveEventResponse(from item: MenuBarItem, initialOrigin: CGPoint, timeout: Duration) async throws -> CGPoint {
        MouseCursor.hide()
        defer { MouseCursor.show() }
        let windowID = item.windowID
        do {
            return try await withTimeout(timeout) {
                while true {
                    try Task.checkCancellation()
                    guard let origin = Bridging.windowFrame(for: windowID)?.origin else {
                        throw EventError.missingItemBounds(item)
                    }
                    if origin != initialOrigin { return origin }
                    await Task.yield()
                }
            }
        } catch let error as EventError {
            throw error
        } catch is TaskTimeoutError {
            throw EventError.itemResponseTimeout(item)
        } catch {
            throw EventError.cannotComplete
        }
    }

    private func postMoveEvents(item: MenuBarItem, destination: MoveDestination) async throws {
        try await acquireEventLock()
        defer { releaseEventLock() }

        var itemOrigin = try currentBounds(for: item).origin
        let points = try targetPoints(forMoving: item, to: destination)
        let cursor = try mouseLocation()
        let source = try eventSource()
        try permitLocalEvents()

        guard
            let mouseDown = CGEvent.menuBarItemEvent(item: item, source: source, type: .move(.mouseDown), location: points.start),
            let mouseUp = CGEvent.menuBarItemEvent(item: destination.targetItem, source: source, type: .move(.mouseUp), location: points.end)
        else {
            throw EventError.eventCreationFailure(item)
        }

        var timeout = moveTimeout(for: item)
        lastMoveOperationDate = .now
        MouseCursor.hide()
        defer {
            MouseCursor.warp(to: cursor)
            MouseCursor.show()
            lastMoveOperationDate = .now
            updateMoveTimeout(timeout, for: item)
        }

        do {
            try await scrombleEvent(mouseDown, item: item, timeout: timeout)
            itemOrigin = try await waitForMoveEventResponse(from: item, initialOrigin: itemOrigin, timeout: timeout)
            // Double mouse up prevents invalid item state.
            try await scrombleEvent(mouseUp, item: item, timeout: timeout, repeating: 2)
            itemOrigin = try await waitForMoveEventResponse(from: item, initialOrigin: itemOrigin, timeout: timeout)
            timeout -= timeout / 4
        } catch {
            do {
                Logger.itemMover.warning("Move events failed, posting fallback")
                try await scrombleEvent(mouseUp, item: item, timeout: .milliseconds(100), repeating: 2)
            } catch {
                Logger.itemMover.error("Fallback failed: \(error)")
            }
            timeout += timeout / 2
            throw error
        }
    }

    func move(item: MenuBarItem, to destination: MoveDestination) async throws {
        guard item.isMovable else { throw EventError.itemNotMovable(item) }
        itemMoveCount += 1
        defer { itemMoveCount -= 1 }

        do {
            try await waitForUserToPauseInput()
        } catch {
            throw EventError.cannotComplete
        }
        appState.interaction.stopAll()
        defer { appState.interaction.startAll() }

        try await waitForMoveOperationBuffer()
        Logger.itemMover.info("Moving \(item.info.description)")

        guard try !itemHasCorrectPosition(item: item, for: destination) else { return }

        MouseCursor.hide()
        defer { MouseCursor.show() }

        let maxAttempts = 8
        for attempt in 1...maxAttempts {
            guard !Task.isCancelled else { throw EventError.cannotComplete }
            do {
                if try itemHasCorrectPosition(item: item, for: destination) { return }
                try await postMoveEvents(item: item, destination: destination)
                return
            } catch {
                Logger.itemMover.debug("Move attempt \(attempt) failed: \(error)")
                if attempt < maxAttempts {
                    try await waitForMoveOperationBuffer()
                    continue
                }
                throw (error as? EventError) ?? EventError.cannotComplete
            }
        }
    }

    func slowMove(item: MenuBarItem, to destination: MoveDestination, timeout: Duration = .seconds(1)) async throws {
        itemMoveCount += 1
        defer { itemMoveCount -= 1 }
        try await move(item: item, to: destination)
        do {
            try await withTimeout(timeout) { [self] in
                while true {
                    try Task.checkCancellation()
                    if try itemHasCorrectPosition(item: item, for: destination) { return }
                    try await Task.sleep(for: .milliseconds(10))
                }
            }
        } catch is TaskTimeoutError {
            throw EventError.itemResponseTimeout(item)
        }
    }

    // MARK: - Clicking

    private func postClickEvents(item: MenuBarItem, mouseButton: CGMouseButton) async throws {
        try await acquireEventLock()
        defer { releaseEventLock() }

        let clickPoint = try currentBounds(for: item).center
        let cursor = try mouseLocation()
        let source = try eventSource()
        try permitLocalEvents()

        let (down, up): (MenuBarItemEventType.ClickSubtype, MenuBarItemEventType.ClickSubtype) = switch mouseButton {
        case .left: (.leftMouseDown, .leftMouseUp)
        case .right: (.rightMouseDown, .rightMouseUp)
        default: (.otherMouseDown, .otherMouseUp)
        }
        let timeout = Duration.milliseconds(250)

        guard
            let mouseDown = CGEvent.menuBarItemEvent(item: item, source: source, type: .click(down), location: clickPoint),
            let mouseUp = CGEvent.menuBarItemEvent(item: item, source: source, type: .click(up), location: clickPoint)
        else {
            throw EventError.eventCreationFailure(item)
        }

        MouseCursor.hide()
        defer {
            MouseCursor.warp(to: cursor)
            MouseCursor.show()
        }

        do {
            try await postEventWithBarrier(mouseDown, to: item, timeout: timeout)
            try await postEventWithBarrier(mouseUp, to: item, timeout: timeout, repeating: 2)
        } catch {
            do {
                Logger.itemMover.warning("Click events failed, posting fallback")
                try await postEventWithBarrier(mouseUp, to: item, timeout: timeout, repeating: 2)
            } catch {
                Logger.itemMover.error("Fallback failed: \(error)")
            }
            throw error
        }
    }

    func click(item: MenuBarItem, with mouseButton: CGMouseButton) async throws {
        do {
            try await waitForUserToPauseInput()
        } catch {
            throw EventError.cannotComplete
        }
        Logger.itemMover.info("Clicking \(item.info.description)")
        appState.interaction.stopAll()
        defer { appState.interaction.startAll() }

        let maxAttempts = 4
        for attempt in 1...maxAttempts {
            guard !Task.isCancelled else { throw EventError.cannotComplete }
            do {
                try await postClickEvents(item: item, mouseButton: mouseButton)
                return
            } catch {
                Logger.itemMover.debug("Click attempt \(attempt) failed: \(error)")
                if attempt < maxAttempts {
                    await eventSleep()
                    continue
                }
                throw (error as? EventError) ?? EventError.cannotComplete
            }
        }
    }

    // MARK: - Temporarily showing

    /// The destination a temporarily shown item returns to, if it is currently shown.
    func returnDestination(forTempShownItem info: MenuBarItemInfo) -> MoveDestination? {
        tempShownContexts.first { $0.info == info }?.returnDestination
    }

    private func returnDestination(for item: MenuBarItem, in items: [MenuBarItem]) -> MoveDestination? {
        guard let index = items.firstIndex(where: { $0.info == item.info }) else { return nil }
        if items.indices.contains(index + 1) { return .leftOfItem(items[index + 1]) }
        if items.indices.contains(index - 1) { return .rightOfItem(items[index - 1]) }
        return nil
    }

    private func runRehideTimer(for interval: TimeInterval? = nil) {
        let interval = interval ?? appState.settings.tempShowInterval
        rehideTimer?.invalidate()
        rehideTimer = .scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.rehideTempShownItems() }
            }
        }
    }

    func tempShowItem(_ item: MenuBarItem, clickWhenFinished: Bool, mouseButton: CGMouseButton) {
        Task { await temporarilyShow(item: item, click: clickWhenFinished, mouseButton: mouseButton) }
    }

    private func temporarilyShow(item: MenuBarItem, click: Bool, mouseButton: CGMouseButton) async {
        if let latest = MenuBarItem(windowID: item.windowID), latest.isOnScreen {
            if click {
                do {
                    try await self.click(item: latest, with: mouseButton)
                } catch {
                    Logger.itemMover.error("Click failed: \(error)")
                }
            }
            return
        }

        guard let screen = NSScreen.screenWithActiveMenuBar ?? NSScreen.main else { return }
        guard let appMenuFrame = ApplicationMenu.frame(for: screen.displayID) else {
            Logger.itemMover.warning("No application menu frame, so not showing \(item.info.description)")
            return
        }

        var items = await MenuBarItem.resolveAll(onScreenOnly: false, activeSpaceOnly: true)
        guard let destination = returnDestination(for: item, in: items) else {
            Logger.itemMover.warning("No return destination for \(item.info.description)")
            return
        }

        if let index = items.firstIndex(where: { $0.info == .hiddenControlItem }) {
            items.removeSubrange(...index)
        }

        var maxX = appMenuFrame.maxX
        if let notch = screen.frameOfNotch {
            // Convert the notch's max X to CoreGraphics space (same X axis).
            maxX = max(maxX, notch.maxX + 30)
        }
        maxX += item.frame.width

        // Remove items until there is enough room to show this one.
        items.trimPrefix { candidate in
            if candidate.isOnScreen && candidate.canBeHidden {
                return candidate.frame.minX <= maxX
            }
            return true
        }

        guard let target = items.first else {
            let alert = NSAlert()
            alert.messageText = String(localized: "Not enough room to show \"\(item.displayName)\"")
            alert.runModal()
            return
        }

        appState.interaction.stopAll()
        defer { appState.interaction.startAll() }

        do {
            try await move(item: item, to: .leftOfItem(target))
        } catch {
            Logger.itemMover.error("Error showing item: \(error)")
            return
        }

        let context = TempShownContext(info: item.info, returnDestination: destination)
        tempShownContexts.append(context)
        rehideTimer?.invalidate()
        defer { runRehideTimer() }

        guard click else { return }
        await eventSleep(for: .milliseconds(100))
        let idsBeforeClick = Set(Bridging.windowList(option: .onScreen))
        do {
            try await self.click(item: item, with: mouseButton)
        } catch {
            Logger.itemMover.error("Error clicking item: \(error)")
            return
        }
        await eventSleep(for: .milliseconds(250))
        context.shownInterfaceWindow = WindowInfo.onScreenWindows().first { window in
            window.ownerPID == item.sourcePID && !idsBeforeClick.contains(window.windowID)
        }
    }

    func rehideTempShownItems() async {
        guard !tempShownContexts.isEmpty else { return }
        guard !tempShownContexts.contains(where: { $0.isShowingInterface }) else {
            runRehideTimer(for: 3)
            return
        }
        guard hasUserPausedInput(for: 0.25) else {
            runRehideTimer(for: 1)
            return
        }

        var current = tempShownContexts
        tempShownContexts.removeAll()
        let items = await MenuBarItem.resolveAll(onScreenOnly: false, activeSpaceOnly: true)
        var failed: [TempShownContext] = []

        appState.interaction.stopAll()
        defer { appState.interaction.startAll() }
        await eventSleep(for: .milliseconds(250))

        MouseCursor.hide()
        defer { MouseCursor.show() }

        while let context = current.popLast() {
            guard let item = items.first(where: { $0.info == context.info }) else { continue }
            do {
                try await move(item: item, to: context.returnDestination)
            } catch {
                context.rehideAttempts += 1
                if context.rehideAttempts < 3 {
                    current.append(context)
                } else {
                    context.rehideAttempts = 0
                    failed.append(context)
                }
            }
        }

        if !failed.isEmpty {
            tempShownContexts.append(contentsOf: failed.reversed())
            runRehideTimer(for: 3)
        }
        await appState.itemStore.refresh()
    }

    func removeTempShownItemFromCache(with info: MenuBarItemInfo) {
        tempShownContexts.removeAll { $0.info == info }
    }

    // MARK: - Control item order

    /// Re-adds the Tuck icon directly right of the hidden divider when any item sits between
    /// them. Returns `true` if the icon was repositioned.
    func enforceDividerAdjacency(hidden: MenuBarItem, tuckIcon: MenuBarItem, items: [MenuBarItem]) -> Bool {
        guard !isMouseButtonDown, !mouseHasRecentlyMoved, !appState.interaction.isDraggingMenuBarItem else { return false }
        guard
            let hiddenFrame = Bridging.windowFrame(for: hidden.windowID),
            let iconFrame = Bridging.windowFrame(for: tuckIcon.windowID)
        else { return false }
        let between = items.filter { item in
            guard item.windowID != tuckIcon.windowID, let frame = Bridging.windowFrame(for: item.windowID) else { return false }
            return frame.minX >= hiddenFrame.maxX && frame.maxX <= iconFrame.minX
        }
        guard !between.isEmpty || iconFrame.maxX <= hiddenFrame.minX else { return false }
        let manager = appState.menuBarManager
        guard let icon = manager.section(named: .visible)?.controlItem, let divider = manager.section(named: .hidden)?.controlItem else { return false }
        Logger.itemMover.info("Repositioning Tuck icon next to the hidden divider")
        icon.reposition(rightOf: divider)
        return true
    }

    func enforceControlItemOrder(hidden: MenuBarItem, alwaysHidden: MenuBarItem) async {
        guard !isMouseButtonDown, !mouseHasRecentlyMoved else { return }
        let hiddenFrame = Bridging.windowFrame(for: hidden.windowID) ?? hidden.frame
        let alwaysHiddenFrame = Bridging.windowFrame(for: alwaysHidden.windowID) ?? alwaysHidden.frame
        guard hiddenFrame.maxX <= alwaysHiddenFrame.minX else { return }
        do {
            try await slowMove(item: alwaysHidden, to: .leftOfItem(hidden))
        } catch {
            Logger.itemMover.error("Failed to enforce control item order: \(error)")
        }
    }
}

// MARK: - Helpers

/// Guarantees a continuation is resumed at most once.
@MainActor
private final class Resumer {
    private var continuation: CheckedContinuation<Void, Error>?

    init(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class TapBox {
    var taps: [EventTap] = []

    func disableAll() {
        taps.forEach { $0.disable() }
        taps.removeAll()
    }
}

private enum MenuBarItemEventType {
    case move(MoveSubtype)
    case click(ClickSubtype)

    enum MoveSubtype {
        case mouseDown, mouseUp
    }

    enum ClickSubtype {
        case leftMouseDown, leftMouseUp, rightMouseDown, rightMouseUp, otherMouseDown, otherMouseUp

        var cgEventType: CGEventType {
            switch self {
            case .leftMouseDown: .leftMouseDown
            case .leftMouseUp: .leftMouseUp
            case .rightMouseDown: .rightMouseDown
            case .rightMouseUp: .rightMouseUp
            case .otherMouseDown: .otherMouseDown
            case .otherMouseUp: .otherMouseUp
            }
        }

        var cgMouseButton: CGMouseButton {
            switch self {
            case .leftMouseDown, .leftMouseUp: .left
            case .rightMouseDown, .rightMouseUp: .right
            case .otherMouseDown, .otherMouseUp: .center
            }
        }

        var clickState: Int64 {
            switch self {
            case .leftMouseDown, .rightMouseDown, .otherMouseDown: 1
            case .leftMouseUp, .rightMouseUp, .otherMouseUp: 0
            }
        }
    }

    var cgEventType: CGEventType {
        switch self {
        case .move(.mouseDown): .leftMouseDown
        case .move(.mouseUp): .leftMouseUp
        case .click(let subtype): subtype.cgEventType
        }
    }

    var cgEventFlags: CGEventFlags {
        if case .move(.mouseDown) = self { return .maskCommand }
        return []
    }

    var cgMouseButton: CGMouseButton {
        switch self {
        case .move: .left
        case .click(let subtype): subtype.cgMouseButton
        }
    }
}

private extension CGEventField {
    static let windowID = CGEventField(rawValue: 0x33)!
    static let menuBarItemEventFields: [CGEventField] = [
        .eventSourceUserData,
        .mouseEventWindowUnderMousePointer,
        .mouseEventWindowUnderMousePointerThatCanHandleThisEvent,
        .windowID,
    ]
}

private extension CGEventFilterMask {
    static let permitAllEvents: CGEventFilterMask = [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents]
}

private extension CGEvent {
    static func menuBarItemEvent(item: MenuBarItem, source: CGEventSource, type: MenuBarItemEventType, location: CGPoint) -> CGEvent? {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type.cgEventType, mouseCursorPosition: location, mouseButton: type.cgMouseButton) else {
            return nil
        }
        event.flags = type.cgEventFlags
        event.setUserData(ObjectIdentifier(event))
        let windowID = Int64(item.windowID)
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: windowID)
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: windowID)
        if case .move = type {
            event.setIntegerValueField(.windowID, value: windowID)
        }
        if case .click(let subtype) = type {
            event.setIntegerValueField(.mouseEventClickState, value: subtype.clickState)
        }
        return event
    }

    static func uniqueNullEvent() -> CGEvent? {
        guard let event = CGEvent(source: nil) else { return nil }
        event.setUserData(ObjectIdentifier(event))
        return event
    }

    func post(to location: EventTap.Location) {
        switch location {
        case .hidEventTap: post(tap: .cghidEventTap)
        case .sessionEventTap: post(tap: .cgSessionEventTap)
        case .annotatedSessionEventTap: post(tap: .cgAnnotatedSessionEventTap)
        case .pid(let pid): postToPid(pid)
        }
    }

    func matches(_ other: CGEvent, byIntegerFields fields: [CGEventField]) -> Bool {
        fields.allSatisfy { getIntegerValueField($0) == other.getIntegerValueField($0) }
    }

    func setTargetPID(_ pid: pid_t) {
        setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
    }

    private func setUserData(_ identifier: ObjectIdentifier) {
        setIntegerValueField(.eventSourceUserData, value: Int64(Int(bitPattern: identifier)))
    }
}

nonisolated private extension Logger {
    static let itemMover = Logger(category: "ItemMover")
}
