import AppKit
import OSLog

/// Applies a spacing offset between menu bar items by adjusting the global
/// `NSStatusItemSpacing`/`NSStatusItemSelectionPadding` defaults, then relaunches every
/// app that owns a menu bar item so the new spacing takes effect.
@MainActor
final class SpacingManager {
    struct RelaunchError: LocalizedError {
        let apps: [String]

        var errorDescription: String? {
            "Failed to relaunch \(apps.joined(separator: ", ")). You may need to log out for the changes to take effect."
        }
    }

    private enum Key: String {
        case spacing = "NSStatusItemSpacing"
        case selectionPadding = "NSStatusItemSelectionPadding"
    }

    /// The system default for both keys, before any offset is applied.
    private static let defaultValue = 16

    /// How long to wait for an app to quit on its own before force terminating it.
    private static let forceTerminateTimeout: Duration = .seconds(1)

    /// Applies the given offset and restarts every app with a menu bar item.
    ///
    /// - Note: Calling this restarts every app that owns a menu bar item.
    func apply(offset: Int) async throws {
        if offset == 0 {
            try? await runDefaultsCommand(["-currentHost", "delete", "-globalDomain", Key.spacing.rawValue])
            try? await runDefaultsCommand(["-currentHost", "delete", "-globalDomain", Key.selectionPadding.rawValue])
        } else {
            let value = String(Self.defaultValue + offset)
            try await runDefaultsCommand(["-currentHost", "write", "-globalDomain", Key.spacing.rawValue, "-int", value])
            try await runDefaultsCommand(["-currentHost", "write", "-globalDomain", Key.selectionPadding.rawValue, "-int", value])
        }

        try? await Task.sleep(for: .milliseconds(100))

        let items = MenuBarItem.all(onScreenOnly: false, activeSpaceOnly: true)
        let pids = Set(items.compactMap(\.sourcePID))

        var failedApps: [String] = []

        await withThrowingTaskGroup(of: Void.self) { group in
            for pid in pids {
                guard
                    let app = NSRunningApplication(processIdentifier: pid),
                    app.bundleIdentifier != "com.apple.controlcenter", // Control Center relaunches itself below.
                    app != .current
                else {
                    continue
                }
                group.addTask { @MainActor in
                    try await Self.relaunch(app)
                }
            }
            while let result = await group.nextResult() {
                if case .failure(let error) = result, let failure = error as? RelaunchFailure {
                    failedApps.append(failure.name)
                }
            }
        }

        try? await Task.sleep(for: .milliseconds(100))
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first?.terminate()

        if !failedApps.isEmpty {
            throw RelaunchError(apps: failedApps)
        }
    }

    /// A named failure raised while relaunching a single app; carries the app's
    /// localized name so it can be reported to the user.
    private struct RelaunchFailure: Error {
        let name: String
    }

    /// Quits and relaunches a single app, throwing ``RelaunchFailure`` if it could not
    /// be brought back afterward.
    private static func relaunch(_ app: NSRunningApplication) async throws {
        guard let bundleIdentifier = app.bundleIdentifier, let bundleURL = app.bundleURL else {
            if let name = app.localizedName {
                throw RelaunchFailure(name: name)
            }
            return
        }

        let pidBeforeRelaunch = app.processIdentifier

        if !app.isTerminated {
            app.terminate()
            var elapsed: Duration = .zero
            let pollInterval: Duration = .milliseconds(50)
            while !app.isTerminated, elapsed < forceTerminateTimeout {
                try? await Task.sleep(for: pollInterval)
                elapsed += pollInterval
            }
            if !app.isTerminated {
                app.forceTerminate()
            }
        }

        let stillRunning = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .contains { !$0.isTerminated }

        if !stillRunning {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.addsToRecentItems = false
            configuration.createsNewApplicationInstance = false
            configuration.promptsUserIfNeeded = false
            do {
                try await NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration)
            } catch {
                Logger.spacingManager.error("Failed to relaunch \(app.localizedName ?? bundleIdentifier, privacy: .public): \(error, privacy: .public)")
                if let name = app.localizedName {
                    throw RelaunchFailure(name: name)
                }
                return
            }
        }

        // Spotlight relaunches itself; only count it as a failure if it never quit.
        if bundleIdentifier == "com.apple.Spotlight" {
            let currentPID = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleIdentifier)
                .first?
                .processIdentifier
            if currentPID == pidBeforeRelaunch, let name = app.localizedName {
                throw RelaunchFailure(name: name)
            }
        }
    }

    /// Runs `/usr/bin/defaults` with the given arguments and awaits its termination.
    private nonisolated func runDefaultsCommand(_ arguments: [String]) async throws {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            process.arguments = arguments
            try process.run()
            process.waitUntilExit()
        }.value
    }
}

nonisolated private extension Logger {
    static let spacingManager = Logger(category: "SpacingManager")
}
