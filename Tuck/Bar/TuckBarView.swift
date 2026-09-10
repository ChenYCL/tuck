import AppKit
import SwiftUI

struct TuckBarView: View {
    @Environment(AppState.self) private var appState

    let section: MenuBarSection.Name
    let screen: NSScreen
    let panel: TuckBarPanel

    private var items: [MenuBarItem] {
        appState.itemStore.cache.managedItems(for: section)
    }

    private var location: TuckBarLocation {
        appState.settings.tuckBarLocation
    }

    private var isVertical: Bool { location.isVertical }
    private var isAttached: Bool { location.isAttached }
    private var isDockStyle: Bool { location.usesDockChrome }

    @State private var hoveredWindowID: CGWindowID?

    private var iconSize: CGFloat {
        isDockStyle ? CGFloat(appState.settings.edgeBarIconSize) : (appState.imageCache.menuBarHeight ?? screen.menuBarHeight)
    }

    private var dockPadding: CGFloat { isDockStyle ? 8 : 0 }
    private var dockSpacing: CGFloat { isDockStyle ? max(6, iconSize * 0.22) : 0 }
    private var magnification: CGFloat { isDockStyle ? CGFloat(appState.settings.edgeBarMagnification) : 1 }

    private var stripThickness: CGFloat {
        if isDockStyle { return iconSize + dockPadding * 2 }
        return appState.imageCache.menuBarHeight ?? screen.menuBarHeight
    }

    /// Follow the real menu bar, which can stay light over a light wallpaper even
    /// when the frontmost app is dark.
    private var menuBarColorScheme: ColorScheme {
        let appearance = appState.menuBarManager.section(named: .visible)?.controlItem.window?.effectiveAppearance
            ?? NSApp.effectiveAppearance
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }

    private var barFill: Color {
        menuBarColorScheme == .dark
            ? Color.black.opacity(0.88)
            : Color.white.opacity(0.94)
    }

    /// Dock uses a continuous rounded rect; the below shelf only rounds the bottom.
    private var cornerRadius: CGFloat {
        if isDockStyle { return min(22, stripThickness / 2) }
        return isAttached ? 6 : 12
    }

    private var barShape: AttachedTabShape {
        AttachedTabShape(attached: location.attachedEdge, cornerRadius: cornerRadius)
    }

    private var barStroke: AttachedTabStroke {
        AttachedTabStroke(attached: location.attachedEdge, cornerRadius: cornerRadius)
    }

    private var showsItems: Bool {
        TuckBarGeometry.showsItems(
            location: location,
            alwaysVisible: appState.settings.tuckBarAlwaysVisible,
            expanded: appState.navigation.isTuckBarExpanded
        )
    }

    var body: some View {
        Group {
            if isDockStyle {
                dockBar
            } else {
                itemStack
                    .background(Color.clear)
                    .frame(width: isVertical ? stripThickness : nil, height: isVertical ? nil : stripThickness)
                    .padding(.horizontal, isVertical ? 0 : (showsItems ? 8 : 6))
                    .padding(.vertical, isVertical ? 8 : 0)
                    .background { barShape.fill(barFill) }
                    .overlay {
                        barStroke.stroke(
                            Color.primary.opacity(menuBarColorScheme == .dark ? 0.16 : 0.10),
                            lineWidth: 0.5
                        )
                    }
                    .clipShape(barShape)
                    .shadow(color: .black.opacity(isAttached ? 0.08 : 0.18), radius: isAttached ? 3 : 8, y: isAttached ? 1 : 3)
            }
        }
        .environment(\.colorScheme, menuBarColorScheme)
        .frame(
            maxWidth: isVertical ? nil : screen.frame.width,
            maxHeight: isVertical ? max(screen.frame.height - screen.menuBarHeight - 8, 40) : nil
        )
        .animation(.spring(duration: 0.28, bounce: 0), value: showsItems)
        .onHover { hovering in
            if hovering {
                panel.cancelCollapse()
                panel.expand()
            } else {
                panel.scheduleCollapse()
            }
        }
    }

    /// Plate stays a rounded material capsule; icons live in a magnifying layout
    /// so they spread apart like the Dock instead of stacking.
    private var dockBar: some View {
        let overflow = iconSize * max(0, magnification - 1)
        let hoveredIndex = items.firstIndex { $0.windowID == hoveredWindowID }
        let plateFill = menuBarColorScheme == .dark
            ? Color.black.opacity(0.78)
            : Color.white.opacity(0.94)
        return ZStack(alignment: location == .right ? .trailing : .leading) {
            Capsule(style: .continuous)
                .fill(plateFill)
                .overlay {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.primary.opacity(menuBarColorScheme == .dark ? 0.28 : 0.10), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(menuBarColorScheme == .dark ? 0.55 : 0.20), radius: 16, y: 0)
                .frame(width: iconSize + dockPadding * 2)

            MagnifyingDockLayout(
                iconSize: iconSize,
                spacing: dockSpacing,
                magnification: magnification,
                hoveredIndex: hoveredIndex,
                growSign: location == .right ? -1 : 1
            ) {
                ForEach(Array(items.enumerated()), id: \.element.windowID) { index, item in
                    dockCell(item, index: index)
                }
            }
            .padding(.vertical, dockPadding)
        }
        .padding(location == .right ? .leading : .trailing, overflow)
        .animation(.spring(duration: 0.22, bounce: 0.08), value: hoveredWindowID)
    }

    @ViewBuilder
    private var itemStack: some View {
        if appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults {
            Text("The Tuck Bar cannot be used with an automatically hidden menu bar")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
        } else if isVertical {
            VStack(spacing: dockSpacing) {
                settingsButton
                itemBody
            }
        } else if location == .below {
            // Handle sits under the clock; items grow left so the left edge is a
            // square shelf, not a chevron inside a round cap.
            HStack(spacing: 0) {
                itemBody
                settingsButton
            }
        } else {
            HStack(spacing: 0) {
                settingsButton
                itemBody
            }
        }
    }

    @ViewBuilder
    private var itemBody: some View {
        if !showsItems {
            EmptyView()
        } else if items.isEmpty {
            EmptyView()
        } else if isVertical {
            ScrollView(.vertical) {
                VStack(spacing: dockSpacing) {
                    ForEach(items, id: \.windowID) { item in
                        dockItem(item)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.center)
            .frame(maxHeight: max(screen.frame.height - screen.menuBarHeight - 48, 40))
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(items, id: \.windowID) { item in
                        dockItem(item)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.trailing)
            .frame(maxWidth: max(screen.frame.width - 16, 40))
        }
    }

    private var settingsButton: some View {
        Button {
            if showsItems, location == .below, appState.settings.tuckBarAlwaysVisible {
                panel.collapseToHandle()
            } else if !showsItems {
                panel.expand()
            } else {
                appState.openSettingsWindow(pane: .layout)
            }
        } label: {
            Group {
                if isDockStyle {
                    Image(systemName: "gearshape")
                        .font(.system(size: iconSize * 0.5, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                } else if !showsItems {
                    Image(systemName: "chevron.compact.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                } else if let image = appState.settings.tuckIcon.image(state: .hideItems, isTemplate: appState.settings.customIconIsTemplate) {
                    Image(nsImage: image)
                } else {
                    Image(systemName: "chevron.compact.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: isDockStyle ? iconSize : 18, height: isDockStyle ? iconSize : 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(showsItems ? String(localized: "Settings") : String(localized: "Show hidden menu bar items"))
        .accessibilityLabel(showsItems ? String(localized: "Settings") : String(localized: "Show hidden menu bar items"))
        .padding(isVertical ? EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0) : EdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 2))
    }

    private func dockItem(_ item: MenuBarItem) -> some View {
        TuckBarItemView(item: item, panel: panel, preferredSize: nil, prefersAppIcon: false)
    }

    private func dockCell(_ item: MenuBarItem, index: Int) -> some View {
        let hovered = items.firstIndex { $0.windowID == hoveredWindowID }
        let distance: CGFloat = hovered == nil ? 99 : CGFloat(abs(hovered! - index))
        let scale = TuckBarGeometry.dockScale(distance: distance, maxScale: magnification)
        let size = iconSize * scale
        return DockItemIconView(item: item, size: size)
            .frame(width: size, height: size)
            .overlay {
                TuckBarItemClickView(item: item, action: { button in
                    if appState.settings.tuckBarAlwaysVisible {
                        panel.collapseToHandle()
                    } else {
                        panel.close()
                    }
                    Task {
                        try? await Task.sleep(for: .milliseconds(25))
                        appState.itemMover.tempShowItem(item, clickWhenFinished: true, mouseButton: button)
                    }
                })
            }
            .onHover { inside in
                hoveredWindowID = inside ? item.windowID : nil
            }
            .zIndex(scale > 1.01 ? 1 : 0)
    }
}

// MARK: - TuckBarItemView

private struct TuckBarItemView: View {
    @Environment(AppState.self) private var appState

    let item: MenuBarItem
    let panel: TuckBarPanel
    var preferredSize: CGFloat? = nil
    var prefersAppIcon: Bool = false

    private var image: NSImage? {
        guard let cgImage = appState.imageCache.images[item.info] else { return nil }
        let scale = appState.imageCache.screen?.backingScaleFactor ?? 2
        let size = CGSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)
        return NSImage(cgImage: cgImage, size: size)
    }

    var body: some View {
        Group {
            if prefersAppIcon {
                ItemFallbackIcon(item: item, size: (preferredSize ?? 18) * 0.86)
            } else if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                ItemFallbackIcon(item: item, size: preferredSize ?? 18)
                    .padding(.horizontal, preferredSize == nil ? 4 : 0)
            }
        }
        .frame(width: preferredSize, height: preferredSize)
        .contentShape(Rectangle())
        .overlay {
            TuckBarItemClickView(item: item, action: performAction)
        }
        .accessibilityLabel(item.displayName)
        .help(item.displayName)
    }

    private func performAction(_ button: CGMouseButton) {
        if appState.settings.tuckBarAlwaysVisible {
            panel.collapseToHandle()
        } else {
            panel.close()
        }
        Task {
            try? await Task.sleep(for: .milliseconds(25))
            appState.itemMover.tempShowItem(item, clickWhenFinished: true, mouseButton: button)
        }
    }
}

// MARK: - TuckBarItemClickView

private struct TuckBarItemClickView: NSViewRepresentable {
    let item: MenuBarItem
    let action: (CGMouseButton) -> Void

    func makeNSView(context: Context) -> ClickCaptureView {
        ClickCaptureView(item: item, action: action)
    }

    func updateNSView(_ nsView: ClickCaptureView, context: Context) {
        nsView.item = item
        nsView.action = action
    }
}

/// Captures left/right clicks without dragging, distinguishing them from the drag
/// gestures used elsewhere for item reordering.
private final class ClickCaptureView: NSView {
    var item: MenuBarItem
    var action: (CGMouseButton) -> Void

    private var lastLeftMouseDownDate = Date.now
    private var lastRightMouseDownDate = Date.now
    private var lastLeftMouseDownLocation = CGPoint.zero
    private var lastRightMouseDownLocation = CGPoint.zero

    init(item: MenuBarItem, action: @escaping (CGMouseButton) -> Void) {
        self.item = item
        self.action = action
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        lastLeftMouseDownDate = .now
        lastLeftMouseDownLocation = NSEvent.mouseLocation
    }

    override func rightMouseDown(with event: NSEvent) {
        super.rightMouseDown(with: event)
        lastRightMouseDownDate = .now
        lastRightMouseDownLocation = NSEvent.mouseLocation
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        guard
            Date.now.timeIntervalSince(lastLeftMouseDownDate) < 0.5,
            distance(lastLeftMouseDownLocation, NSEvent.mouseLocation) < 5
        else { return }
        action(.left)
    }

    override func rightMouseUp(with event: NSEvent) {
        super.rightMouseUp(with: event)
        guard
            Date.now.timeIntervalSince(lastRightMouseDownDate) < 0.5,
            distance(lastRightMouseDownLocation, NSEvent.mouseLocation) < 5
        else { return }
        action(.right)
    }
}
