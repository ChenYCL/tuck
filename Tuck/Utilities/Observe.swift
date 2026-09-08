import Observation

enum Observe {
    /// Runs `body` immediately, then re-runs it on the main actor every time any
    /// observable property accessed inside `body` changes.
    ///
    /// The loop stops when the returned token is deallocated or cancelled.
    @MainActor
    static func track(_ body: @escaping @MainActor () -> Void) -> Token {
        let token = Token()
        loop(token: token, body: body)
        return token
    }

    @MainActor
    private static func loop(token: Token, body: @escaping @MainActor () -> Void) {
        guard token.isActive else { return }
        withObservationTracking {
            body()
        } onChange: { [weak token] in
            guard let token else { return }
            Task { @MainActor in
                loop(token: token, body: body)
            }
        }
    }

    final class Token {
        private(set) var isActive = true
        func cancel() { isActive = false }
    }
}
