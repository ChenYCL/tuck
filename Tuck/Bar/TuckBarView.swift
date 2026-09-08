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

    private var contentHeight: CGFloat {
        let height = appState.imageCache.menuBarHeight ?? screen.menuBarHeight
        return screen.hasNotch ? height - 10 : height
    }

    var body: some View {
        content
            .frame(height: contentHeight)
            .padding(.horizontal, 7)
            .glassEffect(.regular, in: .capsule)
            .padding(5)
            .frame(maxWidth: screen.frame.width)
    }

    @ViewBuilder
    private var content: some View {
        if appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults {
            Text("The Tuck Bar cannot be used with an automatically hidden menu bar")
                .padding(.horizontal, 10)
        } else if items.isEmpty {
            Text("No menu bar items in the \(section.displayName) section")
                .padding(.horizontal, 10)
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(items, id: \.windowID) { item in
                        TuckBarItemView(item: item, panel: panel)
                    }
                }
            }
            .defaultScrollAnchor(.trailing)
        }
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
                    .padding(.horizontal, 6)
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
        panel.close()
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
