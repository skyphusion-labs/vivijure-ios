import SwiftUI
import VivijureKit

struct SettingsView: View {
  @EnvironmentObject private var app: AppState
  @State private var prefsJSON = ""
  @State private var prefsStatus = ""

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

        Section("Notifications & polling") {
          Toggle(
            "Notify when render finishes",
            isOn: Binding(
              get: { app.notificationsEnabled },
              set: { on in Task { await app.setNotificationsEnabled(on) } }
            )
          )
          if app.isPolling, let jid = app.renderJobId {
            LabeledContent("Polling", value: "\(jid) · \(app.renderStatus)")
          } else if app.hasPendingRenderPoll, let jid = app.renderJobId {
            VStack(alignment: .leading, spacing: 4) {
              Text("Pending job \(jid) (\(app.renderStatus))")
                .font(.caption)
              Button("Resume poll") { app.startRenderPoll() }
            }
          }
          Text("Polls resume after relaunch (session blob). beginBackgroundTask extends a short window when you leave the app mid-poll; full BGAppRefresh is not used (entitlement-heavy, still short).")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }

        Section("Studio prefs (GET/PATCH /api/prefs)") {
          if prefsJSON.isEmpty {
            Button("Load prefs") {
              Task { await loadPrefs() }
            }
          } else {
            TextEditor(text: $prefsJSON)
              .font(.system(.caption, design: .monospaced))
              .frame(minHeight: 100)
            Button("Save prefs") {
              Task { await savePrefs() }
            }
          }
          if !prefsStatus.isEmpty {
            Text(prefsStatus).font(.caption2)
          }
        }

        Section("Storage") {
          Button("Refresh usage") {
            Task { await app.refreshStorage() }
          }
          if let u = app.storageUsage {
            LabeledContent("Used bytes", value: "\(u.used_bytes ?? 0)")
            LabeledContent("Objects", value: "\(u.objects ?? 0)")
            if let q = u.quota_bytes {
              LabeledContent("Quota", value: "\(q)")
            }
            if u.over == true {
              Text("Over quota").foregroundStyle(.red)
            }
          }
          Button("Reconcile ledger") {
            Task { await app.reconcileStorage() }
          }
          .disabled(app.busy)
        }

        if app.demoAvailable == true {
          Section("Demo mode") {
            Text("Host has demo AUTH surfaces enabled.")
              .font(.caption2)
              .foregroundStyle(.secondary)
            ForEach(Array(app.demoScenes.enumerated()), id: \.offset) { _, scene in
              let name = scene.stringValue
                ?? scene.objectValue?["id"]?.stringValue
                ?? scene.objectValue?["name"]?.stringValue
                ?? scene.prettyJSON().prefix(40).description
              Button("Render demo: \(name)") {
                Task { await app.runDemoRender(scene: String(name)) }
              }
              .disabled(app.busy)
            }
            if let jid = app.demoJobId {
              Text("Job \(jid): \(app.demoStatus)")
                .font(.caption.monospaced())
            }
            DemoChatRow()
          }
        } else if app.demoAvailable == false {
          Section("Demo mode") {
            Text("Not available on this host (or 404).")
              .font(.caption2)
              .foregroundStyle(.secondary)
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
      .task {
        if let p = app.prefs {
          prefsJSON = p.prettyJSON()
        }
      }
    }
  }

  private func loadPrefs() async {
    guard let client = app.client else { return }
    do {
      let p = try await client.getPrefs()
      app.prefs = p
      prefsJSON = p.prettyJSON()
      prefsStatus = "Loaded"
    } catch {
      prefsStatus = error.localizedDescription
    }
  }

  private func savePrefs() async {
    guard let data = prefsJSON.data(using: .utf8),
          let any = try? JSONSerialization.jsonObject(with: data)
    else {
      prefsStatus = "Invalid JSON"
      return
    }
    await app.savePrefs(JSONValue.from(any))
    prefsStatus = "Saved"
  }
}

struct DemoChatRow: View {
  @EnvironmentObject private var app: AppState
  @State private var message = ""
  @State private var reply = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      TextField("Demo chat message", text: $message)
      Button("Send") {
        Task {
          if let r = await app.runDemoChat(message: message) {
            reply = r
          }
        }
      }
      .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || app.busy)
      if !reply.isEmpty {
        Text(reply).font(.caption)
      }
    }
  }
}
