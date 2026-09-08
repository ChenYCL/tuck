import AppKit
import SwiftUI

/// A single menu bar item shown in a `LayoutBarView`, draggable to rearrange the item.
struct LayoutItemView: View {
    let item: MenuBarItem
    let section: MenuBarSection.Name

    @Environment(AppState.self) private var appState
    @Environment(LayoutDragController.self) private var drag

    private var isUnresponsive: Bool {
        Bridging.responsivity(for: item.eventPID) == .unresponsive
    }

    var body: some View {
        content
            .frame(minWidth: 24, minHeight: 24)
            .overlay(alignment: .topTrailing) {
                if isUnresponsive {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.yellow)
                        .offset(x: 4, y: -4)
                }
            }
            .help(item.displayName)
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .named("layout"))
            } action: { newValue in
                drag.itemFrames[item.info] = newValue
            }
            .gesture(dragGesture)
    }

    @ViewBuilder
    private var content: some View {
        if let cgImage = appState.imageCache.images[item.info] {
            let scale = 1 / (appState.imageCache.screen?.backingScaleFactor ?? 2)
            let size = NSSize(width: CGFloat(cgImage.width) * scale, height: CGFloat(cgImage.height) * scale)
            Image(nsImage: NSImage(cgImage: cgImage, size: size))
                .resizable()
                .frame(width: size.width, height: size.height)
        } else {
            ItemFallbackIcon(item: item)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("layout"))
            .onChanged { value in
                guard !isUnresponsive else { return }
                drag.draggingItem = item
                drag.draggingFrom = section
                drag.dragLocation = value.location
                drag.updateProposal { appState.itemStore.cache.managedItems(for: $0) }
            }
            .onEnded { _ in
                defer { drag.reset() }
                guard !isUnresponsive, let proposal = drag.proposal else { return }
                performMove(to: proposal)
            }
    }

    private func performMove(to proposal: (section: MenuBarSection.Name, index: Int)) {
        let destinationItems = appState.itemStore.cache.managedItems(for: proposal.section).filter { $0.info != item.info }

        let destination: ItemMover.MoveDestination
        if proposal.index < destinationItems.count {
            destination = .leftOfItem(destinationItems[proposal.index])
        } else if let last = destinationItems.last {
            destination = .rightOfItem(last)
        } else {
            let controlItems = MenuBarItem.all(onScreenOnly: false, activeSpaceOnly: true)
            switch proposal.section {
            case .hidden:
                guard let controlItem = controlItems.first(where: { $0.info == .hiddenControlItem }) else { return }
                destination = .leftOfItem(controlItem)
            case .alwaysHidden:
                guard let controlItem = controlItems.first(where: { $0.info == .alwaysHiddenControlItem }) else { return }
                destination = .leftOfItem(controlItem)
            case .visible:
                guard let controlItem = controlItems.first(where: { $0.info == .hiddenControlItem }) else { return }
                destination = .rightOfItem(controlItem)
            }
        }

        if proposal.section == section {
            let originalItems = appState.itemStore.cache.managedItems(for: section)
            if let currentIndex = originalItems.firstIndex(where: { $0.info == item.info }),
               proposal.index == currentIndex || proposal.index == currentIndex + 1 {
                return
            }
        }

        let itemMover = appState.itemMover
        let itemStore = appState.itemStore
        Task {
            try? await Task.sleep(for: .milliseconds(25))
            do {
                try await itemMover.slowMove(item: item, to: destination)
                itemMover.removeTempShownItemFromCache(with: item.info)
                await itemStore.refresh()
            } catch {
                drag.errorMessage = error.localizedDescription
            }
        }
    }
}
