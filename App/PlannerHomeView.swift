import SwiftUI
import UniformTypeIdentifiers
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
            app.persistSession()
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
        .onChange(of: app.selectedProjectId) { newId in
          Task { await app.selectProject(newId) }
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
        HStack {
          Button("Refresh") {
            Task { await app.refreshProjects() }
          }
          if app.selectedProjectId != nil {
            Button("Delete project", role: .destructive) {
              Task { await app.deleteSelectedProject() }
            }
          }
        }
        if app.storyboard != nil, app.selectedProjectId != nil {
          Button("Save storyboard to project") {
            Task { await app.saveStoryboardToProject() }
          }
        }
      }

      Section("Cast slots (A–D)") {
        ForEach($app.castSlots) { $slot in
          VStack(alignment: .leading, spacing: 6) {
            Toggle("Slot \(slot.letter)", isOn: $slot.included)
            if slot.included {
              Picker("From cast library", selection: $slot.boundCastId) {
                Text("inline (type below)").tag("")
                ForEach(app.cast) { m in
                  Text("\(m.name)").tag(m.id)
                }
              }
              if slot.boundCastId.isEmpty {
                TextField("Name", text: $slot.inlineName)
                TextField("Bible", text: $slot.inlineBible, axis: .vertical)
                  .lineLimit(2 ... 4)
              } else if let m = app.cast.first(where: { $0.id == slot.boundCastId }) {
                Text(m.name).font(.subheadline)
                Text(m.bible ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(2)
              }
            }
          }
          .padding(.vertical, 2)
        }
        .onChange(of: app.castSlots) { _ in app.persistSession() }
      }

      Section("Plan") {
        if app.availableModels.isEmpty {
          TextField("Model id", text: $app.planModel)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        } else {
          Picker("Model", selection: $app.planModel) {
            ForEach(app.availableModels, id: \.self) { m in
              Text(m).tag(m)
            }
          }
        }
        TextField("Brief", text: $app.brief, axis: .vertical)
          .lineLimit(6 ... 14)
          .onChange(of: app.brief) { _ in app.persistSession() }
        Button("Plan storyboard") {
          Task { await app.runPlan() }
        }
        .disabled(app.brief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || app.busy)
      }

      if app.storyboard != nil {
        Section("Refine") {
          TextField("Instruction", text: $app.refineInstruction, axis: .vertical)
            .lineLimit(2 ... 6)
          Button("Refine storyboard") {
            Task { await app.runRefine() }
          }
          .disabled(app.busy || app.refineInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }

        Section("Scenes") {
          if app.sceneEdits.isEmpty {
            Text("No scenes").foregroundStyle(.secondary)
          }
          ForEach($app.sceneEdits) { $scene in
            NavigationLink {
              SceneEditorDetailView(scene: $scene)
            } label: {
              VStack(alignment: .leading, spacing: 2) {
                Text(scene.id).font(.headline)
                Text(scene.prompt).font(.caption).lineLimit(2).foregroundStyle(.secondary)
                if let s = scene.targetSeconds {
                  Text(String(format: "%.1fs", s)).font(.caption2)
                }
              }
            }
            .swipeActions {
              Button(role: .destructive) {
                app.deleteScene(at: scene.index)
              } label: {
                Label("Delete", systemImage: "trash")
              }
            }
          }
          Button("Apply scene edits") {
            app.commitSceneEdits()
          }
          Button("Discard scene edits") {
            app.discardSceneEdits()
          }
          .disabled(app.originalStoryboard == nil)
        }

        if !app.yamlPreview.isEmpty {
          Section("YAML preview") {
            Text(app.yamlPreview)
              .font(.system(.caption2, design: .monospaced))
              .textSelection(.enabled)
            Button("Refresh YAML") {
              Task { await app.refreshYaml() }
            }
          }
        }

        Section("Storyboard JSON") {
          if let sb = app.storyboard {
            Text(sb.prettyJSON())
              .font(.system(.caption2, design: .monospaced))
              .textSelection(.enabled)
          }
        }
      }
    }
  }
}

struct SceneEditorDetailView: View {
  @Binding var scene: SceneEdit
  @EnvironmentObject private var app: AppState

  private var useChars: [String] {
    if let sb = app.storyboard {
      let u = StoryboardMutator.useCharacters(from: sb)
      if !u.isEmpty { return u }
    }
    return plannerSlotIDs
  }

  var body: some View {
    Form {
      Section("Identity") {
        LabeledContent("id", value: scene.id)
        TextField("prompt", text: $scene.prompt, axis: .vertical)
          .lineLimit(3 ... 10)
        TextField("act (optional)", text: $scene.act)
        HStack {
          Text("target_seconds")
          TextField("seconds", value: $scene.targetSeconds, format: .number)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
        }
      }
      Section("character_slots") {
        ForEach(useChars, id: \.self) { slot in
          Toggle(slot, isOn: Binding(
            get: { scene.characterSlots.contains(slot) },
            set: { on in
              if on {
                if !scene.characterSlots.contains(slot) {
                  scene.characterSlots.append(slot)
                }
              } else {
                scene.characterSlots.removeAll { $0 == slot }
                if scene.dialogueSlot == slot {
                  scene.dialogueSlot = ""
                  scene.dialogueText = ""
                }
              }
            }
          ))
        }
      }
      Section("dialogue") {
        if scene.characterSlots.isEmpty {
          Text("Add a character_slot to attach dialogue.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        } else {
          Picker("Speaker", selection: $scene.dialogueSlot) {
            Text("(none)").tag("")
            ForEach(scene.characterSlots, id: \.self) { s in
              Text(s).tag(s)
            }
          }
          TextField("Line", text: $scene.dialogueText)
        }
      }
    }
    .navigationTitle(scene.id)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Apply") {
          app.commitSceneEdits()
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
        Section("Bindings (plan slots)") {
          let use = StoryboardMutator.useCharacters(from: app.storyboard!)
          if use.isEmpty {
            Text("Storyboard has no use_characters; bundle ships storyboard only.")
              .font(.footnote)
              .foregroundStyle(.secondary)
          } else {
            ForEach(use, id: \.self) { letter in
              if let idx = app.castSlots.firstIndex(where: { $0.letter == letter }) {
                VStack(alignment: .leading) {
                  Text("Slot \(letter)").font(.headline)
                  Picker("Cast", selection: $app.castSlots[idx].boundCastId) {
                    Text("(none)").tag("")
                    ForEach(app.cast) { m in
                      Text(castLabel(m)).tag(m.id)
                    }
                  }
                  if let m = app.cast.first(where: { $0.id == app.castSlots[idx].boundCastId }) {
                    Text("refs: \(m.refKeys.count) · portrait: \(m.portrait_key != nil ? "yes" : "no")")
                      .font(.caption2)
                      .foregroundStyle(.secondary)
                  }
                }
              }
            }
          }
        }
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
          Text("Bound cast members supply portrait + ref_keys as trainingImages (same as web). Stage more images on the Cast tab.")
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
              Text(castLabel(m)).font(.caption2).foregroundStyle(.secondary)
            }
          }
          Button("Refresh cast") {
            Task { await app.refreshCast() }
          }
        }
      }
    }
  }

  private func castLabel(_ m: CastMember) -> String {
    let portrait = m.portrait_key != nil ? "portrait" : "no portrait"
    return "\(m.name) (\(portrait), \(m.refKeys.count) refs)"
  }
}

// MARK: - Audio

struct AudioStepView: View {
  @EnvironmentObject private var app: AppState
  @State private var status = ""
  @State private var showImporter = false

  var body: some View {
    Form {
      Section {
        Text("Generate a bed, upload BYO audio, analyze BPM, or snap scene durations.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      if let key = app.audioKey {
        Section("Current bed") {
          Text(key).font(.caption.monospaced()).textSelection(.enabled)
          Button("Clear bed") {
            app.audioKey = nil
            app.persistSession()
          }
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
      Section("Upload") {
        Button("Import audio file…") {
          showImporter = true
        }
        .disabled(app.busy)
      }
      Section("BPM / snap") {
        HStack {
          Text("BPM")
          TextField("120", value: $app.bpm, format: .number)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
        }
        HStack {
          Text("Beats / shot")
          TextField("4", value: $app.beatsPerShot, format: .number)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
        }
        Button("Analyze bed BPM") {
          Task { await app.analyzeCurrentAudio() }
        }
        .disabled(app.audioKey == nil || app.busy)
        Button("Snap scene durations to phrase") {
          app.snapScenesToBPM()
        }
        .disabled(app.storyboard == nil)
      }
    }
    .fileImporter(
      isPresented: $showImporter,
      allowedContentTypes: [.audio, .mp3, .wav, .mpeg4Audio],
      allowsMultipleSelection: false
    ) { result in
      switch result {
      case .success(let urls):
        guard let url = urls.first else { return }
        Task { await importAudio(url) }
      case .failure(let err):
        app.lastError = err.localizedDescription
      }
    }
  }

  private func importAudio(_ url: URL) async {
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    do {
      let data = try Data(contentsOf: url)
      let mime: String
      switch url.pathExtension.lowercased() {
      case "wav": mime = "audio/wav"
      case "mp3": mime = "audio/mpeg"
      case "m4a", "mp4": mime = "audio/mp4"
      case "ogg": mime = "audio/ogg"
      default: mime = "application/octet-stream"
      }
      await app.uploadAudioData(data, mime: mime)
    } catch {
      app.lastError = error.localizedDescription
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
              if let key = jo["key"]?.stringValue ?? jo["audio_key"]?.stringValue ?? jo["output_key"]?.stringValue {
                app.audioKey = key
              }
              if ["done", "completed", "failed", "error"].contains(st.lowercased()) { break }
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
          }
        }
        if let key = o["key"]?.stringValue ?? o["audio_key"]?.stringValue {
          app.audioKey = key
        }
        app.persistSession()
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
        Toggle("Keyframes only", isOn: $app.keyframesOnly)
        if let key = app.bundleKey {
          Text("Bundle: \(key)").font(.caption2.monospaced())
        } else {
          Text("No bundle yet; submit may still work if the host accepts storyboard-only.")
            .font(.footnote)
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
  @State private var labelDrafts: [Int: String] = [:]
  @Environment(\.openURL) private var openURL

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
          VStack(alignment: .leading, spacing: 6) {
            Text(r.label ?? r.job_id ?? "#\(r.id)").font(.headline)
            Text("\(r.status ?? "?") · \(r.quality_tier ?? "")")
              .font(.caption)
              .foregroundStyle(.secondary)
            if let err = r.error, !err.isEmpty {
              Text(err).font(.caption2).foregroundStyle(.red)
            }
            if let key = r.output_key {
              Text(key).font(.caption2.monospaced()).lineLimit(2)
              Button("Open artifact") {
                Task {
                  if let url = await app.openArtifact(key: key) {
                    openURL(url)
                  }
                }
              }
            }
            HStack {
              TextField(
                "Label",
                text: Binding(
                  get: { labelDrafts[r.id] ?? r.label ?? "" },
                  set: { labelDrafts[r.id] = $0 }
                )
              )
              Button("Save") {
                let label = labelDrafts[r.id] ?? r.label ?? ""
                Task { await app.patchRenderLabel(id: r.id, label: label) }
              }
            }
            .font(.caption)
          }
          .padding(.vertical, 2)
          .swipeActions {
            Button(role: .destructive) {
              Task { await app.deleteRender(id: r.id) }
            } label: {
              Label("Delete", systemImage: "trash")
            }
          }
        }
      }
    }
    .task { await app.refreshHistory() }
  }
}
