import SwiftUI

/// A drag-and-drop-arrangeable representation of the items in a single menu bar section,
/// shown in the Layout settings pane.
struct LayoutBarView: View {
    let section: MenuBarSection.Name

    @Environment(AppState.self) private var appState
    @Environment(LayoutDragController.self) private var drag

    private var items: [MenuBarItem] {
        // Items macOS pins to the trailing edge (Clock, Control Center) cannot be arranged.
        appState.itemStore.cache.managedItems(for: section).filter(\.isMovable)
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                if items.isEmpty {
                    Text("Drag items here")
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(Array(items.enumerated()), id: \.element.info) { index, item in
                        if isProposedIndex(index) {
                            placeholder
                        }
                        LayoutItemView(item: item, section: section)
                            .opacity(drag.draggingItem?.info == item.info ? 0 : 1)
                    }
                    if isProposedIndex(items.count) {
                        placeholder
                    }
                }
            }
            .padding(.horizontal, 8)
            .animation(.snappy, value: drag.proposal?.index)
            .animation(.snappy, value: drag.proposal?.section)
        }
        .frame(height: 50)
        // Menu bar item captures are mostly white glyphs; a dark bar keeps them legible.
        .background(
            LinearGradient(colors: [Color(white: 0.28), Color(white: 0.18)], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .named("layout"))
        } action: { newValue in
            drag.barFrames[section] = newValue
        }
    }

    private func isProposedIndex(_ index: Int) -> Bool {
        drag.proposal?.section == section && drag.proposal?.index == index
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(.quaternary)
            .frame(width: placeholderWidth, height: 24)
    }

    private var placeholderWidth: CGFloat {
        guard let item = drag.draggingItem else { return 24 }
        return drag.itemFrames[item.info]?.width ?? 24
    }
}
