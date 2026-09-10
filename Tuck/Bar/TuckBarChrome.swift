import SwiftUI

/// Chrome for an extra bar that is physically attached to the menu bar or a screen edge.
///
/// The attached edge is square and unstroked so the bar reads as a continuation,
/// not a floating capsule. Only the free corners are rounded, and only the free
/// edges get a hairline.
struct AttachedTabShape: InsettableShape {
    enum AttachedEdge: Equatable {
        case top
        case left
        case right
        case none
    }

    var attached: AttachedEdge
    var cornerRadius: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let r = max(0, min(cornerRadius, min(rect.width, rect.height) / 2) - insetAmount)
        var path = Path()

        switch attached {
        case .top:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            path.addArc(
                tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                tangent2End: CGPoint(x: rect.maxX - r, y: rect.maxY),
                radius: r
            )
            path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
            path.addArc(
                tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                tangent2End: CGPoint(x: rect.minX, y: rect.maxY - r),
                radius: r
            )
            path.closeSubpath()

        case .left:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            path.addArc(
                tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                tangent2End: CGPoint(x: rect.maxX, y: rect.minY + r),
                radius: r
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            path.addArc(
                tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                tangent2End: CGPoint(x: rect.maxX - r, y: rect.maxY),
                radius: r
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()

        case .right:
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY))
            path.addArc(
                tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                tangent2End: CGPoint(x: rect.minX, y: rect.minY + r),
                radius: r
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
            path.addArc(
                tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                tangent2End: CGPoint(x: rect.minX + r, y: rect.maxY),
                radius: r
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()

        case .none:
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: r, height: r), style: .continuous)
        }

        return path
    }

    func inset(by amount: CGFloat) -> AttachedTabShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

/// Hairline on the free edges only — never along the attached edge,
/// which would visually cut the extra bar off from the menu bar.
struct AttachedTabStroke: Shape {
    var attached: AttachedTabShape.AttachedEdge
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = max(0, min(cornerRadius, min(rect.width, rect.height) / 2))
        var path = Path()

        switch attached {
        case .top:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
            path.addArc(
                tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                tangent2End: CGPoint(x: rect.minX + r, y: rect.maxY),
                radius: r
            )
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
            path.addArc(
                tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                tangent2End: CGPoint(x: rect.maxX, y: rect.maxY - r),
                radius: r
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))

        case .left:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            path.addArc(
                tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                tangent2End: CGPoint(x: rect.maxX, y: rect.minY + r),
                radius: r
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            path.addArc(
                tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                tangent2End: CGPoint(x: rect.maxX - r, y: rect.maxY),
                radius: r
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))

        case .right:
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY))
            path.addArc(
                tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                tangent2End: CGPoint(x: rect.minX, y: rect.minY + r),
                radius: r
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
            path.addArc(
                tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                tangent2End: CGPoint(x: rect.minX + r, y: rect.maxY),
                radius: r
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))

        case .none:
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: r, height: r), style: .continuous)
        }

        return path
    }
}

extension TuckBarLocation {
    var attachedEdge: AttachedTabShape.AttachedEdge {
        switch self {
        case .below: .top
        case .left: .left
        case .right: .right
        case .dynamic, .mousePointer, .tuckIcon: .none
        }
    }
}
