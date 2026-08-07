import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var app: AppState

  var body: some View {
    NavigationStack {
      Form {
        Section("Connection") {
          LabeledContent("URL", value: app.studioURLString)
          LabeledContent("User", value: app.whoami?.user ?? app.whoami?.email ?? "—")
          if app.busy {
            ProgressView()
          }
          Button("Reconnect / refresh") {
            Task { await app.bootstrap() }
          }
          Button("Sign out", role: .destructive) {
            app.signOut()
          }
        }
        if let err = app.lastError {
          Section("Last error") {
            Text(err).font(.caption).foregroundStyle(.red)
          }
        }
        Section("About") {
          Text("Vivijure for iOS is a mobile frontend to the Storyboard Planner. Full website parity is the product bar (see docs/PARITY.md).")
            .font(.footnote)
            .foregroundStyle(.secondary)
          Text("AGPL-3.0-only")
            .font(.caption)
        }
      }
      .navigationTitle("Settings")
    }
  }
}
