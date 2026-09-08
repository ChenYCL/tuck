import AppKit
import SwiftUI

struct SearchView: View {
    let panel: SearchPanel

    @Environment(AppState.self) private var appState
    @State private var query = ""
    @State private var selection: MenuBarItemInfo?
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search menu bar items", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .padding(16)
                .focused($isSearchFieldFocused)

            Divider()

            List(selection: $selection) {
                if query.isEmpty {
                    ForEach(MenuBarSection.Name.allCases, id: \.self) { name in
                        let items = appState.itemStore.cache.managedItems(for: name)
                        if !items.isEmpty {
                            Section(name.displayName) {
                                ForEach(items, id: \.info) { item in
                                    row(for: item).tag(item.info)
                                }
                            }
                        }
                    }
                } else {
                    ForEach(scoredItems, id: \.info) { item in
                        row(for: item).tag(item.info)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .onMoveCommand { moveSelection($0) }
            .onKeyPress(.return) {
                perform()
                return .handled
            }

            Divider()

            HStack {
                Button("Settings…") {
                    panel.close()
                    appState.openSettingsWindow(pane: .general)
                }
                .buttonStyle(.plain)

                Spacer()

                if let item = selectedItem {
                    ShowItemButton(item: item, action: perform)
                }
            }
            .padding(10)
        }
        .frame(width: 560, height: 420)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .task { isSearchFieldFocused = true }
        .onChange(of: query, initial: true) { selectFirst() }
        .onChange(of: appState.itemStore.cache, initial: true) { selectFirst() }
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(for item: MenuBarItem) -> some View {
        HStack(spacing: 10) {
            if let icon = appIcon(for: item) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
            }
            Text(item.displayName)
            Spacer()
            thumbnail(for: item)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func thumbnail(for item: MenuBarItem) -> some View {
        if let image = appState.imageCache.images[item.info]?.trimmingTransparentPixels(around: [.minXEdge, .maxXEdge]) {
            let scale = 1 / (appState.imageCache.screen?.backingScaleFactor ?? 2)
            let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            Image(nsImage: NSImage(cgImage: image, size: size))
                .padding(4)
                .background(.regularMaterial, in: .rect(cornerRadius: 6))
        }
    }

    private func appIcon(for item: MenuBarItem) -> NSImage? {
        if item.info.namespace == .controlCenter {
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.controlcenter")
                .map { NSWorkspace.shared.icon(forFile: $0.path) }
        }
        return item.owningApplication?.icon
    }

    // MARK: - Selection

    private var visibleItems: [MenuBarItem] {
        if query.isEmpty {
            return MenuBarSection.Name.allCases.flatMap { appState.itemStore.cache.managedItems(for: $0) }
        }
        return scoredItems
    }

    private var scoredItems: [MenuBarItem] {
        appState.itemStore.cache.managedItems
            .compactMap { item -> (item: MenuBarItem, score: Int)? in
                guard let score = FuzzyMatcher.score(query: query, candidate: item.displayName) else { return nil }
                return (item, score)
            }
            .sorted { $0.score > $1.score }
            .map(\.item)
    }

    private var selectedItem: MenuBarItem? {
        guard let selection else { return nil }
        return appState.itemStore.cache.managedItems.first { $0.info == selection }
    }

    private func selectFirst() {
        selection = visibleItems.first?.info
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        let items = visibleItems
        guard !items.isEmpty else { return }
        guard let currentIndex = items.firstIndex(where: { $0.info == selection }) else {
            selection = items.first?.info
            return
        }
        switch direction {
        case .up:
            selection = items[max(0, currentIndex - 1)].info
        case .down:
            selection = items[min(items.count - 1, currentIndex + 1)].info
        default:
            break
        }
    }

    // MARK: - Actions

    private func perform() {
        guard let item = selectedItem else { return }
        panel.close()
        Task {
            try? await Task.sleep(for: .milliseconds(25))
            appState.itemMover.tempShowItem(item, clickWhenFinished: true, mouseButton: .left)
        }
    }
}

private struct ShowItemButton: View {
    let item: MenuBarItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(item.isOnScreen ? "Click item" : "Show item")
                Image(systemName: "return")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 10, height: 10)
                    .foregroundStyle(.secondary)
                    .padding(5)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .buttonStyle(.plain)
    }
}
