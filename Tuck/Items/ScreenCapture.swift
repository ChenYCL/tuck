import CoreGraphics
import ScreenCaptureKit

/// A namespace for screen capture operations.
nonisolated enum ScreenCapture {
    /// Returns a Boolean value that indicates whether the app has been granted screen
    /// capture permissions.
    static func checkPermission() -> Bool {
        // Menu bar item windows are owned by Control Center on macOS 26 and their titles
        // are readable regardless of permission, so probe an ordinary on-screen window of
        // another app instead.
        let foreign = WindowInfo.onScreenWindows(excludeDesktop: true).first { window in
            window.ownerPID != ProcessInfo.processInfo.processIdentifier &&
            window.ownerName != "Window Server" &&
            window.layer == 0 &&
            window.frame.width > 100
        }
        if let foreign {
            return foreign.title != nil
        }
        // CGPreflightScreenCaptureAccess() only returns an initial value, but it works as a fallback.
        return CGPreflightScreenCaptureAccess()
    }

    private nonisolated(unsafe) static var lastCheckResult: Bool?

    /// Returns a Boolean value that indicates whether the app has been granted screen
    /// capture permissions.
    ///
    /// The first time this function is called, the permissions state is computed, cached,
    /// and returned. Subsequent calls either return the cached value, or recompute the
    /// permissions state before caching and returning it.
    static func cachedHasPermission(reset: Bool = false) -> Bool {
        if !reset, let lastCheckResult {
            return lastCheckResult
        }
        let result = checkPermission()
        lastCheckResult = result
        return result
    }

    /// Requests screen capture permissions.
    static func requestPermission() {
        // CGRequestScreenCaptureAccess() is broken on recent macOS versions. SCShareableContent
        // requires screen capture permissions, and triggers a request if the user doesn't have them.
        SCShareableContent.getWithCompletionHandler { _, _ in }
    }

    // MARK: - Capture

    /// Captures a composite image of an array of windows.
    ///
    /// - Parameters:
    ///   - windowIDs: The identifiers of the windows to capture.
    ///   - screenBounds: The bounds to capture. Pass `nil` to capture the minimum
    ///     rectangle that encloses the windows.
    ///   - option: Options that specify the image to be captured.
    static func captureWindows(_ windowIDs: [CGWindowID], screenBounds: CGRect? = nil, option: CGWindowImageOption = []) -> CGImage? {
        guard let array = Bridging.makeWindowArray(windowIDs) else { return nil }
        return CGWindowListCreateImageFromArrayShim(screenBounds ?? .null, array, option)?.takeRetainedValue()
    }
}
