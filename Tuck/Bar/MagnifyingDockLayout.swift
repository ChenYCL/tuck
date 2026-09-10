import SwiftUI

/// Lays out icons along a vertical Dock: hovered icon grows, neighbors grow less,
/// and slots expand so glyphs never overlay each other.
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
        let width = iconSize * (hoveredIndex == nil ? 1 : magnification)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        let restEdge = growSign < 0 ? bounds.maxX : bounds.minX
        for (index, subview) in subviews.enumerated() {
            let s = scale(at: index)
            let slot = iconSize * s
            let centerY = y + slot / 2
            let extra = iconSize * (s - 1) / 2
            let centerX: CGFloat
            if growSign < 0 {
                centerX = restEdge - extra - iconSize / 2
            } else if growSign > 0 {
                centerX = restEdge + extra + iconSize / 2
            } else {
                centerX = bounds.midX
            }
            subview.place(
                at: CGPoint(x: centerX, y: centerY),
                anchor: .center,
                proposal: ProposedViewSize(width: iconSize, height: iconSize)
            )
            y += slot + spacing
        }
    }
}
