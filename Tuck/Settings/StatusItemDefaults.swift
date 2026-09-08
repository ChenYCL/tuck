import Foundation

/// Proxy for AppKit's native `NSStatusItem` persistence keys.
nonisolated enum StatusItemDefaults {
    static subscript(preferredPosition autosaveName: String) -> CGFloat? {
        get {
            let key = "NSStatusItem Preferred Position \(autosaveName)"
            guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
            return UserDefaults.standard.double(forKey: key)
        }
        set {
            let key = "NSStatusItem Preferred Position \(autosaveName)"
            if let newValue {
                UserDefaults.standard.set(Double(newValue), forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    static subscript(visible autosaveName: String) -> Bool? {
        get {
            let key = "NSStatusItem Visible \(autosaveName)"
            guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
            return UserDefaults.standard.bool(forKey: key)
        }
        set {
            let key = "NSStatusItem Visible \(autosaveName)"
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
}
