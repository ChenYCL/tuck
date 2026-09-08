import Observation

/// A type that manages the permissions of the app.
@MainActor
@Observable
final class PermissionsManager {
    /// The state of the granted permissions for the app.
    enum State {
        case missing
        case hasRequired
        case hasAll
    }

    let accessibility = AccessibilityPermission()
    let screenRecording = ScreenRecordingPermission()

    /// All permissions managed by this instance.
    var all: [Permission] { [accessibility, screenRecording] }

    /// The state of the granted permissions for the app.
    var state: State {
        if all.contains(where: { $0.isRequired && !$0.hasPermission }) {
            return .missing
        }
        if all.allSatisfy(\.hasPermission) {
            return .hasAll
        }
        return .hasRequired
    }

    /// Re-checks every permission and updates its cached ``Permission/hasPermission`` value.
    func refresh() {
        for permission in all {
            permission.refreshPermission()
        }
    }

    /// Starts polling all permissions.
    func startPolling() {
        for permission in all {
            permission.startPolling()
        }
    }

    /// Stops polling all permissions.
    func stopPolling() {
        for permission in all {
            permission.stopPolling()
        }
    }
}
