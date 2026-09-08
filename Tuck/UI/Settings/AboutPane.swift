import SwiftUI

struct AboutPane: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let updates = appState.updates
        Form {
            Section {
                VStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 128, height: 128)
                    Text(Constants.appName)
                        .font(.largeTitle.bold())
                    Text("Version \(Constants.versionString)")
                        .foregroundStyle(.secondary)
                    Text(Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section("Updates") {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { updates.automaticallyChecksForUpdates },
                    set: { updates.automaticallyChecksForUpdates = $0 }
                ))
                Toggle("Automatically download updates", isOn: Binding(
                    get: { updates.automaticallyDownloadsUpdates },
                    set: { updates.automaticallyDownloadsUpdates = $0 }
                ))
                LabeledContent {
                    Button("Check for Updates…") { updates.checkForUpdates() }
                        .disabled(!updates.canCheckForUpdates)
                } label: {
                    if let date = updates.lastUpdateCheckDate {
                        Text("Last checked: \(date.formatted(date: .abbreviated, time: .shortened))")
                    } else {
                        Text("Last checked: Never")
                    }
                }
            }

            Section {
                HStack {
                    Button("Quit Tuck") { NSApp.terminate(nil) }
                    Spacer()
                    Link("Source Code", destination: Constants.sourceCodeURL)
                    Link("Report a Bug", destination: Constants.reportBugURL)
                }
            }
        }
        .formStyle(.grouped)
    }
}
