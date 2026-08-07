import PhotosUI
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
                    Text(
                      "refs: \(m.refKeys.count) · portrait: \(m.portrait_key != nil ? "yes" : "no") · LoRA: \(m.lora_status ?? "?")"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                  }
                }
              }
            }
          }
        }
        Section("Scene start keyframes (optional)") {
          Text("Upload a start frame per scene; shipped as sceneStartImages on bundle (web Phase 4b).")
            .font(.footnote)
            .foregroundStyle(.secondary)
          let scenes = app.storyboard?.objectValue?["scenes"]?.arrayValue ?? []
          ForEach(Array(scenes.enumerated()), id: \.offset) { idx, scene in
            let sid = StoryboardMutator.sceneId(at: idx, scene: scene)
            SceneStartRow(sceneId: sid, stagedKey: app.sceneStartImages[sid])
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

struct SceneStartRow: View {
  @EnvironmentObject private var app: AppState
  let sceneId: String
  let stagedKey: String?
  @State private var photoItem: PhotosPickerItem?

  var body: some View {
    HStack {
      VStack(alignment: .leading) {
        Text(sceneId).font(.subheadline.weight(.semibold))
        if let key = stagedKey {
          Text(key).font(.caption2.monospaced()).lineLimit(1)
        } else {
          Text("no start image").font(.caption2).foregroundStyle(.secondary)
        }
      }
      Spacer()
      if stagedKey != nil {
        Button("Clear") { app.clearSceneStart(sceneId: sceneId) }
          .font(.caption)
      }
      PhotosPicker(selection: $photoItem, matching: .images) {
        Image(systemName: "photo.badge.plus")
      }
      .onChange(of: photoItem) { item in
        guard let item else { return }
        Task {
          do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let mime = ImageMime.sniff(data) ?? "image/jpeg"
            await app.stageSceneStart(sceneId: sceneId, data: data, mime: mime)
            photoItem = nil
          } catch {
            app.lastError = error.localizedDescription
          }
        }
      }
    }
  }
}

enum ImageMime {
  static func sniff(_ data: Data) -> String? {
    if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
    if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
    if data.count >= 12 {
      let riff = data.prefix(4)
      let webp = data.subdata(in: 8 ..< 12)
      if riff.elementsEqual([0x52, 0x49, 0x46, 0x46]),
         webp.elementsEqual([0x57, 0x45, 0x42, 0x50])
      {
        return "image/webp"
      }
    }
    return nil
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
      Section("Score prompt") {
        TextField("Music prompt", text: $app.scorePrompt, axis: .vertical)
          .lineLimit(3 ... 8)
        Button("Suggest from storyboard") {
          Task { await app.suggestScorePrompt(force: true) }
        }
        .disabled(app.storyboard == nil || app.busy)
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
      let prompt = app.scorePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
      let body = JSONValue.object([
        "storyboard": sb,
        "prompt": .string(
          prompt.isEmpty
            ? "cinematic underscore matching the storyboard mood"
            : prompt
        ),
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

  private var shotCount: Int {
    app.storyboard.flatMap { StoryboardMutator.sceneIds(from: $0).count } ?? 0
  }

  var body: some View {
    Form {
      Section("Options") {
        Picker("Quality", selection: $app.qualityTier) {
          ForEach(app.modules?.qualityTiers ?? ["draft", "standard", "final"], id: \.self) { t in
            Text(t).tag(t)
          }
        }
        if !app.motionBackends.isEmpty {
          Picker("Motion backend", selection: $app.motionBackend) {
            if app.motionBackends.count > 1 {
              Text("(pick required)").tag("")
            }
            ForEach(app.motionBackends, id: \.self) { m in
              Text(m).tag(m)
            }
          }
          .disabled(app.keyframesOnly)
        } else {
          TextField("Motion backend id", text: $app.motionBackend)
            .disabled(app.keyframesOnly)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
        Toggle("Keyframes only", isOn: $app.keyframesOnly)
        if let key = app.bundleKey {
          Text("Bundle: \(key)").font(.caption2.monospaced())
        } else {
          Text("No bundle yet; submit may still work if the host accepts storyboard-only.")
            .font(.footnote)
        }
        if let ak = app.audioKey {
          Text("Audio bed: \(ak)").font(.caption2.monospaced())
        }
      }

      if !app.renderConfigModules.isEmpty {
        Section("Module render config") {
          Text("Render-scope knobs from each module's config_schema (install-scope lives in Modules tab).")
            .font(.caption2)
            .foregroundStyle(.secondary)
          ForEach(app.renderConfigModules) { mod in
            if !mod.fields.isEmpty {
              DisclosureGroup(mod.label) {
                ForEach(mod.fields) { field in
                  RenderFieldControl(field: field)
                }
              }
            }
          }
        }
      }

      Section("Scatter / gather") {
        Toggle("Use scatter render", isOn: $app.useScatter)
          .disabled(shotCount < 2 || app.castLoras.isEmpty || app.keyframesOnly)
        if app.useScatter {
          Stepper("Shards: \(app.scatterShards)", value: $app.scatterShards, in: 2 ... max(2, shotCount))
          Text("Needs >= 2 shots, a bundle, motion backend, and at least one bound cast.")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
      Section {
        Button(app.useScatter ? "Submit scatter render" : "Submit render") {
          Task { await app.runRender() }
        }
        .disabled(app.storyboard == nil || app.busy || (app.useScatter && app.bundleKey == nil))
        if let jid = app.renderJobId {
          Text("Job: \(jid)")
          Text("Status: \(app.renderStatus)")
        }
      }
    }
  }
}

struct RenderFieldControl: View {
  @EnvironmentObject private var app: AppState
  let field: RenderConfigField

  var body: some View {
    switch field.type {
    case "bool":
      Toggle(field.label, isOn: Binding(
        get: {
          if case .bool(let b) = app.renderFieldValues[field.id] { return b }
          if case .bool(let b) = field.defaultValue { return b }
          return false
        },
        set: { app.setRenderField(field, value: .bool($0)) }
      ))
    case "enum":
      Picker(field.label, selection: Binding(
        get: {
          app.renderFieldValues[field.id]?.stringValue
            ?? field.defaultValue?.stringValue
            ?? ""
        },
        set: { v in
          if v.isEmpty {
            app.setRenderField(field, value: nil)
          } else {
            app.setRenderField(field, value: .string(v))
          }
        }
      )) {
        Text("default").tag("")
        ForEach(field.enumValues, id: \.self) { v in
          Text(field.enumLabels[v] ?? v).tag(v)
        }
      }
    case "int", "float":
      HStack {
        Text(field.label)
        Spacer()
        TextField(
          "value",
          text: Binding(
            get: {
              if let d = app.renderFieldValues[field.id]?.doubleValue {
                return field.type == "int" ? String(Int(d)) : String(d)
              }
              if let d = field.defaultValue?.doubleValue {
                return field.type == "int" ? String(Int(d)) : String(d)
              }
              return ""
            },
            set: { raw in
              let t = raw.trimmingCharacters(in: .whitespaces)
              if t.isEmpty {
                app.setRenderField(field, value: nil)
              } else if let d = Double(t) {
                app.setRenderField(field, value: .number(d))
              }
            }
          )
        )
        .keyboardType(.decimalPad)
        .multilineTextAlignment(.trailing)
        .frame(maxWidth: 100)
      }
      if field.min != nil || field.max != nil {
        Text("range \(field.min.map { String($0) } ?? "…") – \(field.max.map { String($0) } ?? "…")")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    default:
      TextField(field.label, text: Binding(
        get: {
          app.renderFieldValues[field.id]?.stringValue
            ?? field.defaultValue?.stringValue
            ?? ""
        },
        set: { v in
          if v.isEmpty {
            app.setRenderField(field, value: nil)
          } else {
            app.setRenderField(field, value: .string(v))
          }
        }
      ))
    }
  }
}

// MARK: - History

struct HistoryStepView: View {
  @EnvironmentObject private var app: AppState
  @State private var labelDrafts: [Int: String] = [:]
  @State private var tagDrafts: [Int: String] = [:]
  @State private var narrationDrafts: [Int: String] = [:]
  @Environment(\.openURL) private var openURL

  var body: some View {
    List {
      Section {
        Button("Refresh") {
          Task { await app.refreshHistory() }
        }
        if !app.renderTags.isEmpty {
          Text("Known tags: \(app.renderTags.joined(separator: ", "))")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
      Section("Renders") {
        if app.renders.isEmpty {
          Text("No renders loaded.").foregroundStyle(.secondary)
        }
        ForEach(app.renders) { r in
          VStack(alignment: .leading, spacing: 6) {
            HStack {
              Text(r.label ?? r.job_id ?? "#\(r.id)").font(.headline)
              if r.isScatterParent {
                Text("scatter")
                  .font(.caption2)
                  .padding(.horizontal, 6)
                  .padding(.vertical, 2)
                  .background(Color.orange.opacity(0.2))
                  .clipShape(Capsule())
              }
            }
            Text("\(r.status ?? "?") · \(r.quality_tier ?? "") · \(r.mode ?? "")")
              .font(.caption)
              .foregroundStyle(.secondary)
            if let tags = r.tags, !tags.isEmpty {
              Text(tags.joined(separator: ", ")).font(.caption2)
            }
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
            if r.bundle_key != nil {
              Button("Load into planner (re-render)") {
                app.loadRenderIntoPlanner(r)
              }
              .font(.caption)
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
            HStack {
              TextField(
                "Tags (comma)",
                text: Binding(
                  get: {
                    tagDrafts[r.id] ?? (r.tags ?? []).joined(separator: ", ")
                  },
                  set: { tagDrafts[r.id] = $0 }
                )
              )
              Button("Tags") {
                let raw = tagDrafts[r.id] ?? ""
                let tags = raw.split(separator: ",")
                  .map { $0.trimmingCharacters(in: .whitespaces) }
                  .filter { !$0.isEmpty }
                Task { await app.patchRenderTags(id: r.id, tags: tags) }
              }
            }
            .font(.caption)
            Button("Add audio bed") {
              Task { await app.addAudioToHistory(id: r.id) }
            }
            .font(.caption)
            .disabled(app.audioKey == nil || app.busy)
            HStack {
              TextField(
                "Narration text",
                text: Binding(
                  get: { narrationDrafts[r.id] ?? "" },
                  set: { narrationDrafts[r.id] = $0 }
                )
              )
              Button("Narrate") {
                let t = narrationDrafts[r.id] ?? ""
                Task { await app.addNarrationToHistory(id: r.id, text: t) }
              }
            }
            .font(.caption)
            Button("Finalize (GPU i2v)") {
              Task { await app.finalizeHistory(id: r.id) }
            }
            .font(.caption)
            .disabled(app.busy)

            if !app.cloudMotionModels.isEmpty || !app.cloudAnimateModel.isEmpty {
              if !app.cloudMotionModels.isEmpty {
                Picker("Cloud model", selection: $app.cloudAnimateModel) {
                  ForEach(app.cloudMotionModels, id: \.self) { m in
                    Text(m).tag(m)
                  }
                }
                .font(.caption)
              }
              Button("Animate cloud i2v") {
                Task { await app.animateCloudHistory(id: r.id) }
              }
              .font(.caption)
              .disabled(app.busy)
              Button("Animate hybrid (default GPU)") {
                Task { await app.animateHybridHistory(id: r.id, defaultBackend: "gpu") }
              }
              .font(.caption)
              .disabled(app.busy)
            }

            let shots = r.keyframeShotIds
            if !shots.isEmpty {
              DisclosureGroup("Keyframes (\(shots.count))") {
                ForEach(shots, id: \.self) { shot in
                  HStack {
                    Text(shot).font(.caption.monospaced())
                    Spacer()
                    let locked = r.resolvedLockedShots.contains(shot)
                    Button(locked ? "Unlock" : "Lock") {
                      Task {
                        await app.toggleLockedShot(
                          renderId: r.id,
                          shotId: shot,
                          currently: r.resolvedLockedShots
                        )
                      }
                    }
                    .font(.caption2)
                    Button("Regen") {
                      Task { await app.regenShot(renderId: r.id, shotId: shot) }
                    }
                    .font(.caption2)
                    .disabled(app.busy || r.bundle_key == nil)
                  }
                }
              }
            }
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
