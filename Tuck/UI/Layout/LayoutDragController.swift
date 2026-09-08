import CoreGraphics
import Observation

/// Tracks the state of an in-progress drag within the Layout settings pane.
@MainActor
@Observable
final class LayoutDragController {
    /// The item currently being dragged, if any.
    var draggingItem: MenuBarItem?

    /// The section the dragged item started in.
    var draggingFrom: MenuBarSection.Name?

    /// The current drag location, in the "layout" named coordinate space.
    var dragLocation: CGPoint = .zero

    /// The most recently reported frame of each item, in the "layout" named coordinate space.
    var itemFrames: [MenuBarItemInfo: CGRect] = [:]

    /// The most recently reported frame of each section's bar, in the "layout" named coordinate space.
    var barFrames: [MenuBarSection.Name: CGRect] = [:]

    /// The section and index the dragged item would be dropped at if released now.
    var proposal: (section: MenuBarSection.Name, index: Int)?

    /// A message to present in an alert, or `nil` if no error is pending.
    var errorMessage: String?

    /// A convenience accessor combining `draggingItem` and `draggingFrom`.
    var dragging: (item: MenuBarItem, from: MenuBarSection.Name)? {
        guard let draggingItem, let draggingFrom else { return nil }
        return (draggingItem, draggingFrom)
    }

    /// Recomputes `proposal` from the current `dragLocation`, using `items` to look up each
    /// section's current items.
    func updateProposal(items: (MenuBarSection.Name) -> [MenuBarItem]) {
        guard let draggingItem else {
            proposal = nil
            return
        }
        guard let section = barFrames.first(where: { $0.value.contains(dragLocation) })?.key else {
            proposal = nil
            return
        }
        let sectionItems = items(section).filter { $0.info != draggingItem.info }
        let index = sectionItems.filter { (itemFrames[$0.info]?.midX ?? .greatestFiniteMagnitude) < dragLocation.x }.count
        proposal = (section, index)
    }

    /// Clears all drag state.
    func reset() {
        draggingItem = nil
        draggingFrom = nil
        dragLocation = .zero
        proposal = nil
    }
}
