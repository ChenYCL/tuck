import CoreGraphics
import Testing
@testable import Tuck

struct TuckBarGeometryTests {
    private let screen = TuckBarGeometry.Screen(
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        menuBarHeight: 24
    )
    private let horizontalBar = CGSize(width: 200, height: 34)
    private let verticalBar = CGSize(width: 40, height: 300)

    @Test func belowAlignsToTrailingEdgeUnderMenuBar() {
        let origin = TuckBarGeometry.origin(
            location: .below,
            barSize: horizontalBar,
            screen: screen,
            mouseX: 100,
            tuckIconMidX: 700,
            isMouseInEmptySpace: false
        )
        #expect(origin.x == 1240)
        #expect(origin.y == 842)
    }

    @Test func leftSitsOnLeadingEdgeBelowMenuBar() {
        let origin = TuckBarGeometry.origin(
            location: .left,
            barSize: verticalBar,
            screen: screen,
            mouseX: 0,
            tuckIconMidX: nil,
            isMouseInEmptySpace: false
        )
        #expect(origin.x == 0)
        #expect(origin.y == 576)
    }

    @Test func rightSitsOnTrailingEdgeBelowMenuBar() {
        let origin = TuckBarGeometry.origin(
            location: .right,
            barSize: verticalBar,
            screen: screen,
            mouseX: 0,
            tuckIconMidX: nil,
            isMouseInEmptySpace: false
        )
        #expect(origin.x == 1400)
        #expect(origin.y == 576)
    }

    @Test func floatingHandleStaysOnScreenAndBelowMenuBar() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = FloatingHandleGeometry.origin(
            normalized: CGPoint(x: 1, y: 1),
            size: 48,
            screen: screen,
            menuBarHeight: 24
        )
        #expect(origin.x == 1380)
        #expect(origin.y == 816)

        let normalized = FloatingHandleGeometry.normalized(
            origin: origin,
            size: 48,
            screen: screen,
            menuBarHeight: 24
        )
        #expect(normalized.x == 1)
        #expect(normalized.y == 1)
    }

    @Test func attachedEdgesMatchPlacement() {
        #expect(TuckBarLocation.below.attachedEdge == .top)
        #expect(TuckBarLocation.left.attachedEdge == .left)
        #expect(TuckBarLocation.right.attachedEdge == .right)
        #expect(TuckBarLocation.mousePointer.attachedEdge == .none)
    }

    @Test func belowAlwaysVisibleStaysCollapsedUntilExpanded() {
        #expect(TuckBarGeometry.showsItems(location: .below, alwaysVisible: true, expanded: false) == false)
        #expect(TuckBarGeometry.showsItems(location: .below, alwaysVisible: true, expanded: true) == true)
        #expect(TuckBarGeometry.showsItems(location: .left, alwaysVisible: true, expanded: false) == true)
        #expect(TuckBarGeometry.showsItems(location: .below, alwaysVisible: false, expanded: false) == true)
    }

    @Test func attachedBarsSitFlushAndPointerBarsLeaveAGap() {
        #expect(TuckBarGeometry.menuBarGap(for: .below) == 0)
        #expect(TuckBarGeometry.menuBarGap(for: .left) == 0)
        #expect(TuckBarGeometry.menuBarGap(for: .mousePointer) == 4)
    }

    @Test func leftAndRightAreVertical() {
        #expect(TuckBarGeometry.axis(for: .left) == .vertical)
        #expect(TuckBarGeometry.axis(for: .right) == .vertical)
        #expect(TuckBarGeometry.axis(for: .below) == .horizontal)
        #expect(TuckBarGeometry.axis(for: .dynamic) == .horizontal)
    }

    @Test func mousePointerCentersOnMouseAndClampsToScreen() {
        let centered = TuckBarGeometry.origin(
            location: .mousePointer,
            barSize: horizontalBar,
            screen: screen,
            mouseX: 500,
            tuckIconMidX: 100,
            isMouseInEmptySpace: true
        )
        #expect(centered.x == 400)

        let clamped = TuckBarGeometry.origin(
            location: .mousePointer,
            barSize: horizontalBar,
            screen: screen,
            mouseX: 10,
            tuckIconMidX: nil,
            isMouseInEmptySpace: true
        )
        #expect(clamped.x == 0)
    }

    @Test func tuckIconFallsBackToMouseWhenIconFrameIsMissing() {
        let origin = TuckBarGeometry.origin(
            location: .tuckIcon,
            barSize: horizontalBar,
            screen: screen,
            mouseX: 500,
            tuckIconMidX: nil,
            isMouseInEmptySpace: false
        )
        #expect(origin.x == 400)
    }

    @Test func tallLeftBarClampsOntoTheScreen() {
        let origin = TuckBarGeometry.origin(
            location: .left,
            barSize: CGSize(width: 40, height: 2000),
            screen: screen,
            mouseX: 0,
            tuckIconMidX: nil,
            isMouseInEmptySpace: false
        )
        #expect(origin.y == 0)
    }
}
