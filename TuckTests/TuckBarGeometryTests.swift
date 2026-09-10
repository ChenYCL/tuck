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

    @Test func leftDockIsCenteredAndInset() {
        let origin = TuckBarGeometry.origin(
            location: .left,
            barSize: verticalBar,
            screen: screen,
            mouseX: 0,
            tuckIconMidX: nil,
            isMouseInEmptySpace: false,
            edgeInset: 12
        )
        #expect(origin.x == 12)
        #expect(origin.y == 288)
    }

    @Test func rightDockIsCenteredAndInset() {
        let origin = TuckBarGeometry.origin(
            location: .right,
            barSize: verticalBar,
            screen: screen,
            mouseX: 0,
            tuckIconMidX: nil,
            isMouseInEmptySpace: false,
            edgeInset: 12
        )
        #expect(origin.x == 1388)
        #expect(origin.y == 288)
    }

    @Test func floatingHandleFollowsCursorOntoAnotherScreen() {
        let laptop = FloatingHandleGeometry.ScreenSpec(
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            menuBarHeight: 24
        )
        let external = FloatingHandleGeometry.ScreenSpec(
            frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
            menuBarHeight: 30
        )
        let origin = FloatingHandleGeometry.clampedOrigin(
            cursor: CGPoint(x: -200, y: 500),
            size: 48,
            screens: [laptop, external]
        )
        #expect(origin.x < 0)
        #expect(origin.x >= -1920 + 12)
        #expect(origin.x <= -1920 + 1920 - 48 - 12)
    }

    @Test func floatingHandleUsesNearestScreenWhenCursorIsInAGap() {
        let bottom = FloatingHandleGeometry.ScreenSpec(
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            menuBarHeight: 24
        )
        let top = FloatingHandleGeometry.ScreenSpec(
            frame: CGRect(x: 0, y: 1100, width: 1920, height: 1080),
            menuBarHeight: 30
        )
        let screen = FloatingHandleGeometry.screenContaining(
            CGPoint(x: 100, y: 1000),
            screens: [bottom, top]
        )
        #expect(screen?.frame.minY == 1100)
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

    @Test func dockMagnificationFallsOffWithDistance() {
        #expect(abs(TuckBarGeometry.dockScale(distance: 0, maxScale: 1.6) - 1.6) < 0.0001)
        #expect(abs(TuckBarGeometry.dockScale(distance: 2.2, maxScale: 1.6) - 1) < 0.0001)
        let neighbor = TuckBarGeometry.dockScale(distance: 1, maxScale: 1.6)
        #expect(neighbor > 1)
        #expect(neighbor < 1.6)
    }

    @Test func dockMapsSystemExtrasToSymbols() {
        #expect(DockItemIcon.symbolName(title: "com.apple.menuextra.wifi", displayName: "Wi-Fi", namespace: "com.apple.controlcenter") == "wifi")
        #expect(DockItemIcon.symbolName(title: "com.apple.menuextra.battery", displayName: "Battery", namespace: nil) == "battery.100percent")
        #expect(DockItemIcon.symbolName(title: "NowPlaying", displayName: "Now Playing", namespace: nil) == "play.circle.fill")
    }

    @Test func attachedEdgesMatchPlacement() {
        #expect(TuckBarLocation.below.attachedEdge == .top)
        #expect(TuckBarLocation.left.attachedEdge == .none)
        #expect(TuckBarLocation.right.attachedEdge == .none)
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
        #expect(TuckBarGeometry.edgeInset(for: .left, configured: 12) == 12)
        #expect(TuckBarGeometry.edgeInset(for: .below, configured: 12) == 0)
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
