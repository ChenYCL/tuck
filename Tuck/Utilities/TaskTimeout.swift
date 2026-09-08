import Foundation

struct TaskTimeoutError: Error {}

/// Runs `operation` on the main actor, throwing `TaskTimeoutError` if it does not
/// finish within `timeout`.
@MainActor
func withTimeout<T>(_ timeout: Duration, operation: @escaping @MainActor () async throws -> T) async throws -> T {
    let work = Task { try await operation() }
    let timer = Task {
        try await Task.sleep(for: timeout)
        work.cancel()
    }
    defer { timer.cancel() }
    do {
        return try await work.value
    } catch is CancellationError where timer.isCancelled == false {
        throw TaskTimeoutError()
    }
}
