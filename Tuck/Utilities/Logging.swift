import OSLog

nonisolated extension Logger {
    init(category: String) {
        self.init(subsystem: Constants.bundleIdentifier, category: category)
    }
}
