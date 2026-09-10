import SwiftUI

/// Vertical Dock layout. Slots grow with magnification so icons never share pixels.
struct MagnifyingDockLayout: Layout {
    var iconSize: CGFloat
    var spacing: CGFloat
    var magnification: CGFloat
    var hoveredIndex: Int?
    var growSign: CGFloat
    var range: CGFloat = 2.2

    func scale(at index: Int) -> CGFloat {
        guard let hoveredIndex else { return 1 }
        return TuckBarGeometry.dockScale(
            distance: CGFloat(abs(index - hoveredIndex)),
            range: range,
            maxScale: magnification
        )
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let scales = subviews.indices.map { scale(at: $0) }
        let height = scales.reduce(CGFloat(0)) { $0 + iconSize * $1 } + spacing * CGFloat(max(0, subviews.count - 1))
        let width = iconSize * max(1, hoveredIndex == nil ? 1 : magnification)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        let restEdge = growSign < 0 ? bounds.maxX : bounds.minX
        for (index, subview) in subviews.enumerated() {
            let slot = iconSize * scale(at: index)
            let centerY = y + slot / 2
            let centerX: CGFloat
            if growSign < 0 {
                centerX = restEdge - slot / 2
            } else if growSign > 0 {
                centerX = restEdge + slot / 2
            } else {
                centerX = bounds.midX
            }
            subview.place(
                at: CGPoint(x: centerX, y: centerY),
                anchor: .center,
                proposal: ProposedViewSize(width: slot, height: slot)
            )
            y += slot + spacing
        }
    }
}
