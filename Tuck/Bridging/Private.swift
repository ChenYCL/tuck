import CoreGraphics
import ApplicationServices

// MARK: - Bridged Types

typealias CGSConnectionID = Int32
typealias CGSSpaceID = size_t

nonisolated enum CGSSpaceType: UInt32 {
    case user = 0
    case system = 2
    case fullscreen = 4
}

nonisolated struct CGSSpaceMask: OptionSet {
    let rawValue: UInt32

    static let includesCurrent = CGSSpaceMask(rawValue: 1 << 0)
    static let includesOthers = CGSSpaceMask(rawValue: 1 << 1)
    static let includesUser = CGSSpaceMask(rawValue: 1 << 2)

    static let includesVisible = CGSSpaceMask(rawValue: 1 << 16)

    static let allSpaces: CGSSpaceMask = [.includesUser, .includesOthers, .includesCurrent]
    static let allVisibleSpaces: CGSSpaceMask = [.includesVisible, .allSpaces]
}

// MARK: - CGSConnection Functions

@_silgen_name("CGSMainConnectionID")
nonisolated func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSCopyConnectionProperty")
nonisolated func CGSCopyConnectionProperty(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ key: CFString,
    _ outValue: inout Unmanaged<CFTypeRef>?
) -> CGError

@_silgen_name("CGSSetConnectionProperty")
nonisolated func CGSSetConnectionProperty(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ key: CFString,
    _ value: CFTypeRef
) -> CGError

// MARK: - CGSEvent Functions

@_silgen_name("CGSEventIsAppUnresponsive")
nonisolated func CGSEventIsAppUnresponsive(
    _ cid: CGSConnectionID,
    _ psn: inout ProcessSerialNumber
) -> Bool

// MARK: - CGSSpace Functions

@_silgen_name("CGSGetActiveSpace")
nonisolated func CGSGetActiveSpace(_ cid: CGSConnectionID) -> CGSSpaceID

@_silgen_name("CGSCopySpacesForWindows")
nonisolated func CGSCopySpacesForWindows(
    _ cid: CGSConnectionID,
    _ mask: CGSSpaceMask,
    _ windowIDs: CFArray
) -> Unmanaged<CFArray>?

@_silgen_name("CGSSpaceGetType")
nonisolated func CGSSpaceGetType(
    _ cid: CGSConnectionID,
    _ sid: CGSSpaceID
) -> CGSSpaceType

// MARK: - CGSWindow Functions

@_silgen_name("CGSGetWindowList")
nonisolated func CGSGetWindowList(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ count: Int32,
    _ list: UnsafeMutablePointer<CGWindowID>,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetOnScreenWindowList")
nonisolated func CGSGetOnScreenWindowList(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ count: Int32,
    _ list: UnsafeMutablePointer<CGWindowID>,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetProcessMenuBarWindowList")
nonisolated func CGSGetProcessMenuBarWindowList(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ count: Int32,
    _ list: UnsafeMutablePointer<CGWindowID>,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetWindowCount")
nonisolated func CGSGetWindowCount(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetOnScreenWindowCount")
nonisolated func CGSGetOnScreenWindowCount(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetScreenRectForWindow")
nonisolated func CGSGetScreenRectForWindow(
    _ cid: CGSConnectionID,
    _ wid: CGWindowID,
    _ outRect: inout CGRect
) -> CGError

// MARK: - Process Serial Number

/// Returns a PSN for a given PID.
@_silgen_name("GetProcessForPID")
nonisolated func GetProcessForPID(
    _ pid: pid_t,
    _ psn: inout ProcessSerialNumber
) -> OSStatus

// MARK: - CGWindowList

/// `CGWindowListCreateImageFromArray` is obsoleted in the macOS 26 SDK, but the symbol
/// still exists and is the only way to capture offscreen menu bar items.
@_silgen_name("CGWindowListCreateImageFromArray")
nonisolated func CGWindowListCreateImageFromArrayShim(
    _ screenBounds: CGRect,
    _ windowArray: CFArray,
    _ imageOption: CGWindowImageOption
) -> Unmanaged<CGImage>?

// MARK: - Accessibility

/// Returns the window ID backing an accessibility element.
@_silgen_name("_AXUIElementGetWindow")
nonisolated func _AXUIElementGetWindow(_ element: AXUIElement, _ outWindowID: inout CGWindowID) -> AXError

@_silgen_name("CGSCopyActiveMenuBarDisplayIdentifier")
nonisolated func CGSCopyActiveMenuBarDisplayIdentifier(_ cid: CGSConnectionID) -> Unmanaged<CFString>?

@_silgen_name("CGSGetWindowLevel")
nonisolated func CGSGetWindowLevel(_ cid: CGSConnectionID, _ wid: CGWindowID, _ outLevel: inout CGWindowLevel) -> CGError

@_silgen_name("CGDisplayGetDisplayIDFromUUID")
nonisolated func CGDisplayGetDisplayIDFromUUID(_ uuid: CFUUID) -> CGDirectDisplayID
