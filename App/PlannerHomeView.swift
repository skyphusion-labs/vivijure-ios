import SwiftUI
import VivijureKit

struct PlannerHomeView: View {
  @EnvironmentObject private var app: AppState

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        statusBanner
        stepPicker
        Divider()
        stepBody
      }
      .navigationTitle("Planner")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("New") { app.clearPlannerSession() }
        }
      }
    }
  }

  private var statusBanner: some View {
    VStack(alignment: .leading, spacing: 4) {
      if app.busy {
        ProgressView().frame(maxWidth: .infinity)
      }
      if let err = app.lastError {
        Text(err).font(.caption).foregroundStyle(.red)
      } else if !app.statusMessage.isEmpty {
        Text(app.statusMessage).font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal)
    .padding(.vertical, 6)
  }

  private var stepPicker: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(AppState.PlannerStep.allCases) { step in
          Button {
            app.plannerStep = step
            if step == .history {
              Task { await app.refreshHistory() }
            }
          } label: {
            Text(step.rawValue)
              .font(.subheadline.weight(app.plannerStep == step ? .semibold : .regular))
              .padding(.horizontal, 12)
              .padding(.vertical, 8)
              .background(app.plannerStep == step ? Color.accentColor.opacity(0.2) : Color.clear)
              .clipShape(Capsule())
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal)
      .padding(.vertical, 8)
    }
  }

  @ViewBuilder
  private var stepBody: some View {
    switch app.plannerStep {
    case .plan: PlanStepView()
    case .castBundle: CastBundleStepView()
    case .audio: AudioStepView()
    case .render: RenderStepView()
    case .history: HistoryStepView()
    }
  }
}

// MARK: - Plan

struct PlanStepView: View {
  @EnvironmentObject private var app: AppState
  @State private var newProjectName = ""

  var body: some View {
    Form {
      Section("Project") {
        Picker("Active project", selection: $app.selectedProjectId) {
          Text("(transient)").tag(Optional<Int>.none)
          ForEach(app.projects) { p in
            Text(p.name).tag(Optional(p.id))
          }
        }
        HStack {
          TextField("New project name", text: $newProjectName)
          Button("Create") {
            let n = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !n.isEmpty else { return }
            Task {
              await app.createProject(name: n)
              newProjectName = ""
            }
          }
        }
        Button("Refresh projects") {
          Task { await app.refreshProjects() }
        }
      }
      Section("Plan") {
        TextField("Model id", text: $app.planModel)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        TextField("Brief", text: $app.brief, axis: .vertical)
          .lineLimit(6 ... 14)
        Button("Plan storyboard") {
          Task { await app.runPlan() }
        }
        .disabled(app.brief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || app.busy)
      }
      if let sb = app.storyboard {
        Section("Storyboard") {
          Text(sb.prettyJSON())
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
        }
      }
    }
  }
}

// MARK: - Cast & Bundle

struct CastBundleStepView: View {
  @EnvironmentObject private var app: AppState

  var body: some View {
    Form {
      if app.storyboard == nil {
        Section {
          Text("Plan a storyboard first.")
            .foregroundStyle(.secondary)
        }
      } else {
        Section("Preflight") {
          Button("Run preflight") {
            Task { await app.runPreflight() }
          }
          .disabled(app.busy)
          if let pf = app.preflight {
            Text(pf.ok ? "OK" : "Issues present")
              .foregroundStyle(pf.ok ? .green : .orange)
            if let issues = pf.issues {
              Text(JSONValue.array(issues).prettyJSON())
                .font(.system(.caption2, design: .monospaced))
            }
          }
        }
        Section("Bundle") {
          Text("Training images per slot: use Cast tab to stage refs, then bundle. Empty refs object works for boards that do not need LoRA uploads.")
            .font(.footnote)
            .foregroundStyle(.secondary)
          Button("Assemble bundle") {
            Task { await app.runBundle() }
          }
          .disabled(app.busy)
          if let key = app.bundleKey {
            Text("bundleKey: \(key)")
              .font(.caption.monospaced())
              .textSelection(.enabled)
          }
        }
        Section("Cast on studio") {
          ForEach(app.cast) { m in
            VStack(alignment: .leading) {
              Text(m.name).font(.headline)
              Text(m.id).font(.caption2).foregroundStyle(.secondary)
              if let st = m.lora_status {
                Text("LoRA: \(st)").font(.caption)
              }
            }
          }
          Button("Refresh cast") {
            Task { await app.refreshCast() }
          }
        }
      }
    }
  }
}

// MARK: - Audio

struct AudioStepView: View {
  @EnvironmentObject private var app: AppState
  @State private var status = ""

  var body: some View {
    Form {
      Section {
        Text("Upload a bed or run score-bed when a score module is installed. BPM snap and beat analyze land next.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      if let key = app.audioKey {
        Section("Current bed") {
          Text(key).font(.caption.monospaced())
        }
      }
      Section("Score bed") {
        Button("Generate music (score-bed)") {
          Task { await score() }
        }
        .disabled(app.storyboard == nil || app.busy)
        if !status.isEmpty {
          Text(status).font(.caption)
        }
      }
      Section("Photos / files") {
        Text("Use the share sheet or Files in a later build for multi-format pickers. Kit already exposes uploadAudio/uploadImage.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func score() async {
    guard let client = app.client, let sb = app.storyboard else { return }
    app.busy = true
    defer { app.busy = false }
    do {
      let body = JSONValue.object([
        "storyboard": sb,
        "prompt": .string("cinematic underscore matching the storyboard mood"),
      ])
      let resp = try await client.scoreBed(body: body)
      status = resp.prettyJSON()
      if case .object(let o) = resp {
        if let jid = o["jobId"]?.stringValue ?? o["job_id"]?.stringValue ?? o["id"]?.stringValue {
          status = "job \(jid); polling…"
          for _ in 0 ..< 40 {
            let job = try await client.pollJob(id: jid)
            if case .object(let jo) = job {
              let st = jo["status"]?.stringValue ?? jo["phase"]?.stringValue ?? ""
              status = "job \(jid): \(st)"
              if ["done", "completed", "failed", "error"].contains(st.lowercased()) { break }
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
          }
        }
        if let key = o["key"]?.stringValue ?? o["audio_key"]?.stringValue {
          app.audioKey = key
        }
      }
    } catch {
      app.lastError = error.localizedDescription
    }
  }
}

// MARK: - Render

struct RenderStepView: View {
  @EnvironmentObject private var app: AppState

  var body: some View {
    Form {
      Section("Options") {
        Picker("Quality", selection: $app.qualityTier) {
          ForEach(app.modules?.qualityTiers ?? ["draft", "standard", "final"], id: \.self) { t in
            Text(t).tag(t)
          }
        }
        if let key = app.bundleKey {
          Text("Bundle: \(key)").font(.caption2.monospaced())
        } else {
          Text("No bundle yet; submit may still work if the host accepts storyboard-only.").font(.footnote)
        }
      }
      Section {
        Button("Submit render") {
          Task { await app.runRender() }
        }
        .disabled(app.storyboard == nil || app.busy)
        if let jid = app.renderJobId {
          Text("Job: \(jid)")
          Text("Status: \(app.renderStatus)")
        }
      }
    }
  }
}

// MARK: - History

struct HistoryStepView: View {
  @EnvironmentObject private var app: AppState

  var body: some View {
    List {
      Section {
        Button("Refresh") {
          Task { await app.refreshHistory() }
        }
      }
      Section("Renders") {
        if app.renders.isEmpty {
          Text("No renders loaded.").foregroundStyle(.secondary)
        }
        ForEach(app.renders) { r in
          VStack(alignment: .leading, spacing: 4) {
            Text(r.label ?? r.job_id ?? "#\(r.id)").font(.headline)
            Text("\(r.status ?? "?") · \(r.quality_tier ?? "")")
              .font(.caption)
              .foregroundStyle(.secondary)
            if let err = r.error, !err.isEmpty {
              Text(err).font(.caption2).foregroundStyle(.red)
            }
            if let key = r.output_key {
              Text(key).font(.caption2.monospaced())
            }
          }
          .padding(.vertical, 2)
        }
      }
    }
    .task { await app.refreshHistory() }
  }
}
