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

    private var stripThickness: CGFloat {
        appState.imageCache.menuBarHeight ?? screen.menuBarHeight
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
            ? Color.black.opacity(0.42)
            : Color.white.opacity(0.78)
    }

    /// Small enough that a 33pt-tall bar reads as a shelf, not a capsule.
    private var cornerRadius: CGFloat { isAttached ? 6 : 12 }

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
        itemStack
            .frame(width: isVertical ? stripThickness : nil, height: isVertical ? nil : stripThickness)
            .padding(.horizontal, isVertical ? 0 : (showsItems ? 8 : 6))
            .padding(.vertical, isVertical ? 8 : 0)
            .background {
                barShape.fill(barFill)
            }
            .overlay {
                barStroke.stroke(
                    Color.primary.opacity(menuBarColorScheme == .dark ? 0.16 : 0.10),
                    lineWidth: 0.5
                )
            }
            .clipShape(barShape)
            .environment(\.colorScheme, menuBarColorScheme)
            .shadow(color: .black.opacity(isAttached ? 0.08 : 0.18), radius: isAttached ? 3 : 8, y: isAttached ? 1 : 3)
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

    @ViewBuilder
    private var itemStack: some View {
        if appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults {
            Text("The Tuck Bar cannot be used with an automatically hidden menu bar")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
        } else if isVertical {
            VStack(spacing: 0) {
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
                VStack(spacing: 0) {
                    ForEach(items, id: \.windowID) { item in
                        TuckBarItemView(item: item, panel: panel)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.top)
            .frame(maxHeight: max(screen.frame.height - screen.menuBarHeight - 16, 40))
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(items, id: \.windowID) { item in
                        TuckBarItemView(item: item, panel: panel)
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
                if !showsItems {
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
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(showsItems ? String(localized: "Settings") : String(localized: "Show hidden menu bar items"))
        .accessibilityLabel(showsItems ? String(localized: "Settings") : String(localized: "Show hidden menu bar items"))
        .padding(isVertical ? EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0) : EdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 2))
    }
}

// MARK: - TuckBarItemView

private struct TuckBarItemView: View {
    @Environment(AppState.self) private var appState

    let item: MenuBarItem
    let panel: TuckBarPanel

    private var image: NSImage? {
        guard let cgImage = appState.imageCache.images[item.info] else { return nil }
        let scale = appState.imageCache.screen?.backingScaleFactor ?? 2
        let size = CGSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)
        return NSImage(cgImage: cgImage, size: size)
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
            } else {
                ItemFallbackIcon(item: item)
                    .padding(.horizontal, 4)
            }
        }
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
