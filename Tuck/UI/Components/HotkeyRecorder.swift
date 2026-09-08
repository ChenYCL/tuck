import SwiftUI

struct HotkeyRecorder: View {
    let action: HotkeyAction

    @Environment(AppState.self) private var appState
    @State private var isRecording = false
    @State private var monitor: EventMonitor?
    @State private var showReservedAlert = false

    private var combination: KeyCombination? {
        appState.settings.hotkeys[action]
    }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                if isRecording { stopRecording() } else { startRecording() }
            } label: {
                Text(leadingText)
                    .frame(maxWidth: .infinity)
            }
            .frame(width: 100)

            Divider().frame(height: 14)

            Button {
                if isRecording {
                    stopRecording()
                } else if combination != nil {
                    appState.settings.hotkeys[action] = nil
                } else {
                    startRecording()
                }
            } label: {
                Image(systemName: trailingSymbol)
                    .frame(width: 30)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 132, height: 24)
        .background(.quaternary, in: Capsule())
        .overlay {
            Capsule().strokeBorder(isRecording ? Color.accentColor : .clear, lineWidth: 1.5)
        }
        .alert("Hotkey is reserved by macOS", isPresented: $showReservedAlert) {
            Button("OK") {}
        }
        .onDisappear { stopRecording() }
    }

    private var leadingText: String {
        if isRecording { return String(localized: "Type Hotkey") }
        if let combination { return combination.stringValue }
        return String(localized: "Record Hotkey")
    }

    private var trailingSymbol: String {
        if isRecording { return "escape" }
        if combination != nil { return "xmark.circle.fill" }
        return "record.circle"
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        appState.hotkeyCenter.suspend(action)
        let monitor = EventMonitor(mask: .keyDown, scope: .local) { event in
            handle(event)
            return nil
        }
        monitor.start()
        self.monitor = monitor
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        monitor?.stop()
        monitor = nil
        appState.hotkeyCenter.resume(action)
    }

    private func handle(_ event: NSEvent) {
        guard let combination = KeyCombination(event: event) else {
            NSSound.beep()
            return
        }
        if combination.modifiers.isEmpty {
            if combination.key == .escape {
                stopRecording()
            } else {
                NSSound.beep()
            }
            return
        }
        if combination.modifiers == .shift {
            NSSound.beep()
            return
        }
        if combination.isReservedBySystem {
            showReservedAlert = true
            return
        }
        appState.settings.hotkeys[action] = combination
        stopRecording()
    }
}
