//
//  KeyCombination.swift
//  Tuck
//

import Carbon.HIToolbox
import Cocoa
import OSLog

/// A key code paired with a set of modifiers, uniquely identifying a hotkey.
nonisolated struct KeyCombination: Codable, Hashable {
    let key: KeyCode
    let modifiers: Modifiers

    /// A string representation of this key combination, suitable for display.
    var stringValue: String {
        modifiers.symbolicValue + key.stringValue
    }

    init(key: KeyCode, modifiers: Modifiers) {
        self.key = key
        self.modifiers = modifiers
    }

    /// Creates a key combination from a key-down, key-up, or flags-changed event.
    ///
    /// Returns `nil` if the event carries no meaningful key code.
    init?(event: NSEvent) {
        switch event.type {
        case .keyDown, .keyUp, .flagsChanged:
            self.init(key: KeyCode(rawValue: Int(event.keyCode)), modifiers: Modifiers(nsEventFlags: event.modifierFlags))
        default:
            return nil
        }
    }
}

// MARK: - System Reserved

nonisolated extension KeyCombination {
    /// The set of key combinations reserved by the system for its own hotkeys.
    static var systemReserved: Set<KeyCombination> {
        Set(reservedBySystem())
    }

    /// Returns a Boolean value that indicates whether this key
    /// combination is reserved for system use.
    var isReservedBySystem: Bool {
        Self.systemReserved.contains(self)
    }

    private static func reservedBySystem() -> [KeyCombination] {
        var symbolicHotkeys: Unmanaged<CFArray>?
        let status = CopySymbolicHotKeys(&symbolicHotkeys)

        guard status == noErr else {
            Logger.keyCombination.error("CopySymbolicHotKeys returned invalid status: \(status)")
            return []
        }
        guard let reservedHotkeys = symbolicHotkeys?.takeRetainedValue() as? [[String: Any]] else {
            Logger.keyCombination.error("Failed to serialize symbolic hotkeys")
            return []
        }

        return reservedHotkeys.compactMap { hotkey in
            guard
                hotkey[kHISymbolicHotKeyEnabled] as? Bool == true,
                let keyCode = hotkey[kHISymbolicHotKeyCode] as? Int,
                let modifiers = hotkey[kHISymbolicHotKeyModifiers] as? Int
            else {
                return nil
            }
            return KeyCombination(
                key: KeyCode(rawValue: keyCode),
                modifiers: Modifiers(carbonFlags: modifiers)
            )
        }
    }
}

// MARK: - Codable

nonisolated extension KeyCombination {
    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        guard container.count == 2 else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected 2 encoded values, found \(container.count ?? 0)"
                )
            )
        }
        self.key = try KeyCode(rawValue: container.decode(Int.self))
        self.modifiers = try Modifiers(rawValue: container.decode(Int.self))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(key.rawValue)
        try container.encode(modifiers.rawValue)
    }
}

// MARK: - Logger

private nonisolated extension Logger {
    static let keyCombination = Logger(category: "KeyCombination")
}
