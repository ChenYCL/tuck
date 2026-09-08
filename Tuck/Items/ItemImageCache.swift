import AppKit
import OSLog

/// Caches live screen-capture images of menu bar items for consumers that need to
/// display them without moving the real items (Layout pane, Search panel, Tuck Bar).
@MainActor
@Observable
final class ItemImageCache {
    @ObservationIgnored private unowned let appState: AppState

    /// The cached item images, keyed by item info.
    private(set) var images: [MenuBarItemInfo: CGImage] = [:]

    /// The screen of the cached item images.
    private(set) var screen: NSScreen?

    /// The height of the menu bar of the cached item images.
    private(set) var menuBarHeight: CGFloat?

    @ObservationIgnored private var observeToken: Observe.Token?
    @ObservationIgnored private var layoutTimer: Timer?
    @ObservationIgnored private var isUpdating = false

    init(appState: AppState) {
        self.appState = appState
    }

    /// Sets up the cache, wiring it to the consumers that need item images.
    func setup() {
        observeToken = Observe.track { [weak self] in
            self?.reactToNavigationChange()
        }
    }

    // MARK: - Consumer Tracking

    private func reactToNavigationChange() {
        let isLayoutVisible = appState.navigation.isSettingsPresented && appState.navigation.selectedPane == .layout
        let isSearchVisible = appState.navigation.isSearchPresented
        let isTuckBarVisible = appState.navigation.isTuckBarPresented

        if isLayoutVisible {
            startLayoutTimer()
            requestUpdate(sections: MenuBarSection.Name.allCases)
        } else {
            stopLayoutTimer()
        }

        if isSearchVisible {
            // Reading the cache here is what subscribes this tracking pass to cache changes.
            _ = appState.itemStore.cache
            requestUpdate(sections: MenuBarSection.Name.allCases)
        }

        if isTuckBarVisible {
            _ = appState.itemStore.cache
            if let section = appState.tuckBar.currentSection {
                requestUpdate(sections: [section])
            }
        }

        if !isLayoutVisible, !isSearchVisible, !isTuckBarVisible {
            stopLayoutTimer()
            images.removeAll()
        }
    }

    private func startLayoutTimer() {
        guard layoutTimer == nil else { return }
        layoutTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.requestUpdate(sections: MenuBarSection.Name.allCases)
            }
        }
    }

    private func stopLayoutTimer() {
        layoutTimer?.invalidate()
        layoutTimer = nil
    }

    private func requestUpdate(sections: [MenuBarSection.Name]) {
        guard !isUpdating else { return }
        isUpdating = true
        Task { [weak self] in
            guard let self else { return }
            await updateCache(sections: sections)
            isUpdating = false
        }
    }

    // MARK: - Cache Update

    /// Updates the cache for the given sections, if the necessary conditions are met.
    func updateCache(sections: [MenuBarSection.Name]) async {
        guard
            ScreenCapture.cachedHasPermission(),
            !appState.itemMover.isMovingItem,
            !appState.itemMover.itemHasRecentlyMoved,
            let screen = NSScreen.main
        else {
            return
        }

        var newImages: [MenuBarItemInfo: CGImage] = [:]

        for section in sections {
            let items = appState.itemStore.cache[section]
            guard !items.isEmpty else { continue }
            let sectionImages = await captureImages(for: items, screen: screen)
            guard !sectionImages.isEmpty else {
                Logger.itemImageCache.warning("Update image cache failed for section \(String(describing: section))")
                continue
            }
            newImages.merge(sectionImages) { _, new in new }
        }

        images.merge(newImages) { _, new in new }
        self.screen = screen
        menuBarHeight = screen.menuBarHeight
    }

    /// Resolves live window frames for `items` on the main actor, then hands the
    /// resulting Sendable data off to a detached task to perform the actual capture.
    private func captureImages(for items: [MenuBarItem], screen: NSScreen) async -> [MenuBarItemInfo: CGImage] {
        let scale = screen.backingScaleFactor
        let displayMinY = CGDisplayBounds(screen.displayID).minY
        let defaultItemThickness = NSStatusBar.system.thickness * scale

        var infos: [CGWindowID: MenuBarItemInfo] = [:]
        var frames: [CGWindowID: CGRect] = [:]
        var windowIDs: [CGWindowID] = []
        var unionFrame = CGRect.null

        for item in items {
            let windowID = item.windowID
            guard
                // Use the most up-to-date window frame.
                let itemFrame = Bridging.windowFrame(for: windowID),
                itemFrame.minY == displayMinY
            else {
                continue
            }
            infos[windowID] = item.info
            frames[windowID] = itemFrame
            windowIDs.append(windowID)
            unionFrame = unionFrame.union(itemFrame)
        }

        guard !windowIDs.isEmpty else { return [:] }

        return await Task.detached(priority: .utility) {
            Self.capture(
                windowIDs: windowIDs,
                infos: infos,
                frames: frames,
                unionFrame: unionFrame,
                scale: scale,
                defaultItemThickness: defaultItemThickness
            )
        }.value
    }

    /// Performs the actual window-list capture off the main actor. Only ever operates
    /// on the Sendable data handed to it; never touches AppKit or shared state.
    private nonisolated static func capture(
        windowIDs: [CGWindowID],
        infos: [CGWindowID: MenuBarItemInfo],
        frames: [CGWindowID: CGRect],
        unionFrame: CGRect,
        scale: CGFloat,
        defaultItemThickness: CGFloat
    ) -> [MenuBarItemInfo: CGImage] {
        var images: [MenuBarItemInfo: CGImage] = [:]
        let option: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]

        if
            let compositeImage = ScreenCapture.captureWindows(windowIDs, option: option),
            CGFloat(compositeImage.width) == unionFrame.width * scale
        {
            for windowID in windowIDs {
                guard let info = infos[windowID], let itemFrame = frames[windowID] else { continue }
                let cropRect = CGRect(
                    x: (itemFrame.minX - unionFrame.minX) * scale,
                    y: (itemFrame.minY - unionFrame.minY) * scale,
                    width: itemFrame.width * scale,
                    height: itemFrame.height * scale
                )
                guard let itemImage = compositeImage.cropping(to: cropRect) else { continue }
                images[info] = itemImage
            }
        } else {
            Logger.itemImageCache.warning("Composite image capture failed. Capturing items individually.")
            for windowID in windowIDs {
                guard let info = infos[windowID], let itemFrame = frames[windowID] else { continue }
                let cropRect = CGRect(
                    x: 0,
                    y: ((itemFrame.height * scale) / 2) - (defaultItemThickness / 2),
                    width: itemFrame.width * scale,
                    height: defaultItemThickness
                )
                guard
                    let itemImage = ScreenCapture.captureWindows([windowID], option: option),
                    let croppedImage = itemImage.cropping(to: cropRect)
                else {
                    continue
                }
                images[info] = croppedImage
            }
        }

        return images
    }
}

// MARK: - Logger

nonisolated private extension Logger {
    static let itemImageCache = Logger(category: "ItemImageCache")
}
