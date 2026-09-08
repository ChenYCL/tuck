//
//  Bridging.swift
//  Tuck

import CoreGraphics
import Foundation
import OSLog

/// A namespace for bridged, low-level window server functionality.
nonisolated enum Bridging {
    /// The display that currently hosts the active menu bar.
    static var activeMenuBarDisplayID: CGDirectDisplayID? {
        guard let string = CGSCopyActiveMenuBarDisplayIdentifier(connectionID)?.takeRetainedValue() else { return nil }
        guard let uuid = CFUUIDCreateFromString(nil, string) else { return nil }
        let id = CGDisplayGetDisplayIDFromUUID(uuid)
        return id == 0 ? nil : id
    }

    /// Creates a `CFArray` of window ID bit patterns, as expected by the `CGWindowList` APIs.
    static func makeWindowArray(_ windowIDs: [CGWindowID]) -> CFArray? {
        var pointers: [UnsafeRawPointer?] = windowIDs.compactMap { UnsafeRawPointer(bitPattern: UInt($0)) }
        guard !pointers.isEmpty else { return nil }
        return CFArrayCreate(nil, &pointers, pointers.count, nil)
    }

    private static let connectionID = CGSMainConnectionID()
}

// MARK: - CGSConnection

nonisolated extension Bridging {
    /// Sets a value for the given key in the current connection to the window server.
    ///
    /// - Parameters:
    ///   - value: The value to set for `key`.
    ///   - key: A key associated with the current connection to the window server.
    static func setConnectionProperty(_ value: CFTypeRef, forKey key: String) {
        let result = CGSSetConnectionProperty(
            connectionID,
            connectionID,
            key as CFString,
            value
        )
        if result != .success {
            Logger.bridging.error("CGSSetConnectionProperty failed with error \(result.rawValue)")
        }
    }

    /// Returns the value for the given key in the current connection to the window server.
    ///
    /// - Parameter key: A key associated with the current connection to the window server.
    /// - Returns: The value associated with `key` in the current connection to the window server.
    static func getConnectionProperty(forKey key: String) -> CFTypeRef? {
        var value: Unmanaged<CFTypeRef>?
        let result = CGSCopyConnectionProperty(
            connectionID,
            connectionID,
            key as CFString,
            &value
        )
        if result != .success {
            Logger.bridging.error("CGSCopyConnectionProperty failed with error \(result.rawValue)")
        }
        return value?.takeRetainedValue()
    }
}

// MARK: - CGSWindow

nonisolated extension Bridging {
    /// Returns the frame for the window with the specified identifier.
    ///
    /// - Parameter windowID: An identifier for a window.
    /// - Returns: The frame -- specified in screen coordinates -- of the window associated
    ///   with `windowID`, or `nil` if the operation failed.
    static func windowFrame(for windowID: CGWindowID) -> CGRect? {
        var rect = CGRect.zero
        let result = CGSGetScreenRectForWindow(connectionID, windowID, &rect)
        guard result == .success else {
            Logger.bridging.error("CGSGetScreenRectForWindow failed with error \(result.rawValue)")
            return nil
        }
        return rect
    }
}

// MARK: Private Window List Helpers

nonisolated extension Bridging {
    private static func getWindowCount() -> Int {
        var count: Int32 = 0
        let result = CGSGetWindowCount(connectionID, 0, &count)
        if result != .success {
            Logger.bridging.error("CGSGetWindowCount failed with error \(result.rawValue)")
        }
        return Int(count)
    }

    private static func getOnScreenWindowCount() -> Int {
        var count: Int32 = 0
        let result = CGSGetOnScreenWindowCount(connectionID, 0, &count)
        if result != .success {
            Logger.bridging.error("CGSGetOnScreenWindowCount failed with error \(result.rawValue)")
        }
        return Int(count)
    }

    private static func getWindowList() -> [CGWindowID] {
        let windowCount = getWindowCount()
        var list = [CGWindowID](repeating: 0, count: windowCount)
        var realCount: Int32 = 0
        let result = CGSGetWindowList(
            connectionID,
            0,
            Int32(windowCount),
            &list,
            &realCount
        )
        guard result == .success else {
            Logger.bridging.error("CGSGetWindowList failed with error \(result.rawValue)")
            return []
        }
        return [CGWindowID](list[..<Int(realCount)])
    }

    private static func getOnScreenWindowList() -> [CGWindowID] {
        let windowCount = getOnScreenWindowCount()
        var list = [CGWindowID](repeating: 0, count: windowCount)
        var realCount: Int32 = 0
        let result = CGSGetOnScreenWindowList(
            connectionID,
            0,
            Int32(windowCount),
            &list,
            &realCount
        )
        guard result == .success else {
            Logger.bridging.error("CGSGetOnScreenWindowList failed with error \(result.rawValue)")
            return []
        }
        return [CGWindowID](list[..<Int(realCount)])
    }

    private static func getMenuBarWindowList() -> [CGWindowID] {
        let windowCount = getWindowCount()
        var list = [CGWindowID](repeating: 0, count: windowCount)
        var realCount: Int32 = 0
        let result = CGSGetProcessMenuBarWindowList(
            connectionID,
            0,
            Int32(windowCount),
            &list,
            &realCount
        )
        guard result == .success else {
            Logger.bridging.error("CGSGetProcessMenuBarWindowList failed with error \(result.rawValue)")
            return []
        }
        return [CGWindowID](list[..<Int(realCount)])
    }

    private static func getOnScreenMenuBarWindowList() -> [CGWindowID] {
        let onScreenList = Set(getOnScreenWindowList())
        return getMenuBarWindowList().filter(onScreenList.contains)
    }
}

// MARK: Public Window List API

nonisolated extension Bridging {
    /// Options that determine the window identifiers to return in a window list.
    struct WindowListOption: OptionSet {
        let rawValue: Int

        /// Specifies windows that are currently on-screen.
        static let onScreen = WindowListOption(rawValue: 1 << 0)

        /// Specifies windows that represent items in the menu bar.
        static let menuBarItems = WindowListOption(rawValue: 1 << 1)

        /// Specifies windows on the currently active space.
        static let activeSpace = WindowListOption(rawValue: 1 << 2)
    }

    /// Returns a list of window identifiers using the given options.
    ///
    /// - Parameter option: Options that filter the returned list.
    static func windowList(option: WindowListOption = []) -> [CGWindowID] {
        let list = if option.contains(.menuBarItems) {
            if option.contains(.onScreen) {
                getOnScreenMenuBarWindowList()
            } else {
                getMenuBarWindowList()
            }
        } else if option.contains(.onScreen) {
            getOnScreenWindowList()
        } else {
            getWindowList()
        }
        return if option.contains(.activeSpace) {
            list.filter(isWindowOnActiveSpace)
        } else {
            list
        }
    }
}

// MARK: - CGSSpace

nonisolated extension Bridging {
    /// The identifier of the active space.
    static var activeSpaceID: CGSSpaceID {
        CGSGetActiveSpace(connectionID)
    }

    /// Returns an array of identifiers for the spaces containing the window with
    /// the given identifier.
    ///
    /// - Parameter windowID: An identifier for a window.
    private static func spaceList(for windowID: CGWindowID) -> [CGSSpaceID] {
        guard let spaces = CGSCopySpacesForWindows(connectionID, .allSpaces, [windowID] as CFArray) else {
            Logger.bridging.error("CGSCopySpacesForWindows failed")
            return []
        }
        guard let spaceIDs = spaces.takeRetainedValue() as? [CGSSpaceID] else {
            Logger.bridging.error("CGSCopySpacesForWindows returned array of unexpected type")
            return []
        }
        return spaceIDs
    }

    /// Returns a Boolean value that indicates whether the window with the
    /// given identifier is on the active space.
    ///
    /// - Parameter windowID: An identifier for a window.
    static func isWindowOnActiveSpace(_ windowID: CGWindowID) -> Bool {
        spaceList(for: windowID).contains(activeSpaceID)
    }

    /// Returns a Boolean value that indicates whether the space with the given
    /// identifier is a fullscreen space.
    ///
    /// - Parameter spaceID: An identifier for a space.
    static func isSpaceFullscreen(_ spaceID: CGSSpaceID) -> Bool {
        CGSSpaceGetType(connectionID, spaceID) == .fullscreen
    }
}

// MARK: - Process Responsivity

nonisolated extension Bridging {
    /// Constants that indicate the responsivity of an app.
    enum Responsivity {
        case responsive, unresponsive, unknown
    }

    /// Returns the responsivity of the given process.
    ///
    /// - Parameter pid: The Unix process identifier of the process to check.
    static func responsivity(for pid: pid_t) -> Responsivity {
        var psn = ProcessSerialNumber()
        let result = GetProcessForPID(pid, &psn)
        guard result == noErr else {
            Logger.bridging.error("GetProcessForPID failed with error \(result)")
            return .unknown
        }
        return CGSEventIsAppUnresponsive(connectionID, &psn) ? .unresponsive : .responsive
    }
}

// MARK: - Logger

nonisolated private extension Logger {
    static let bridging = Logger(category: "Bridging")
}
