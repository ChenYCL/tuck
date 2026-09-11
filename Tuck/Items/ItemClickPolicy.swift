import Foundation

/// When the Tuck Bar is in use, hidden items still have CG windows that report
/// `isOnScreen` even though they sit under the application menu. Clicking those
/// frames on macOS 26 hits Control Center and opens System Settings.
enum ItemClickPolicy {
    static func shouldClickInPlace(
        isOnScreen: Bool,
        section: MenuBarSection.Name?,
        useTuckBar: Bool
    ) -> Bool {
        guard isOnScreen else { return false }
        if useTuckBar {
            return section == .visible
        }
        return true
    }
}
