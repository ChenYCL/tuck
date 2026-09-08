import Foundation

nonisolated enum Constants {
    static let bundleIdentifier = Bundle.main.bundleIdentifier!
    static let appName = "Tuck"
    static let settingsWindowID = "SettingsWindow"
    static let permissionsWindowID = "PermissionsWindow"

    static let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    static let versionString = "\(shortVersion) (\(build))"

    static let sourceCodeURL = URL(string: "https://github.com/zerx-lab/Tuck")!
    static let reportBugURL = URL(string: "https://github.com/zerx-lab/Tuck/issues")!
}
