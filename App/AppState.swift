import Foundation
import SwiftUI
import VivijureKit

/// One plan-stage cast slot (web A–D).
struct PlanCastSlot: Identifiable, Equatable {
  var id: String { letter }
  var letter: String
  var included: Bool = false
  var boundCastId: String = ""
  var inlineName: String = ""
  var inlineBible: String = ""
}

@MainActor
final class AppState: ObservableObject {
  @Published var studioURLString: String = ""
  @Published var token: String = ""
  @Published var isConfigured: Bool = false
  @Published var whoami: WhoamiResponse?
  @Published var modules: ModulesResponse?
  @Published var statusMessage: String = ""
  @Published var lastError: String?

  // Planner session (mirrors web localStorage session)
  @Published var projects: [StoryboardProject] = []
  @Published var selectedProjectId: Int?
  @Published var brief: String = ""
  @Published var planModel: String = ""
  @Published var availableModels: [String] = []
  @Published var storyboard: JSONValue?
  @Published var originalStoryboard: JSONValue?
  @Published var sceneEdits: [SceneEdit] = []
  @Published var yamlPreview: String = ""
  @Published var preflight: PreflightResponse?
  @Published var bundleKey: String?
  @Published var renderJobId: String?
  @Published var renderStatus: String = ""
  @Published var cast: [CastMember] = []
  @Published var renders: [RenderRow] = []
  @Published var plannerStep: PlannerStep = .plan
  @Published var qualityTier: String = "final"
  @Published var keyframesOnly: Bool = false
  @Published var audioKey: String?
  @Published var bpm: Double = 120
  @Published var beatsPerShot: Double = 4
  @Published var refineInstruction: String = ""
  @Published var castSlots: [PlanCastSlot] = plannerSlotIDs.map { PlanCastSlot(letter: $0) }
  @Published var busy: Bool = false

  private let urlKey = "studio_url"
  private let tokenKey = "studio_token"
  private let sessionKey = "planner_session_v1"

  enum PlannerStep: String, CaseIterable, Identifiable {
    case plan = "Plan"
    case castBundle = "Cast & Bundle"
    case audio = "Audio"
    case render = "Render"
    case history = "History"
    var id: String { rawValue }
  }

  init() {
    studioURLString = KeychainStore.get(account: urlKey)
      ?? UserDefaults.standard.string(forKey: urlKey)
      ?? ""
    token = KeychainStore.get(account: tokenKey) ?? ""
    isConfigured = !studioURLString.isEmpty && !token.isEmpty
    restoreSession()
  }

  var client: VivijureClient? {
    guard isConfigured,
          let url = URL(string: studioURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
          url.scheme != nil
    else { return nil }
    return VivijureClient(baseURL: url, bearerToken: token)
  }

  var castBindings: [String: String] {
    var map: [String: String] = [:]
    for slot in castSlots where slot.included && !slot.boundCastId.isEmpty {
      map[slot.letter] = slot.boundCastId
    }
    return map
  }

  func saveCredentials(url: String, token: String) {
    let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
    let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
    studioURLString = u
    self.token = t
    KeychainStore.set(u, account: urlKey)
    KeychainStore.set(t, account: tokenKey)
    UserDefaults.standard.set(u, forKey: urlKey)
    isConfigured = !u.isEmpty && !t.isEmpty
  }

  func signOut() {
    KeychainStore.delete(account: tokenKey)
    token = ""
    isConfigured = false
    whoami = nil
    modules = nil
    clearPlannerSession()
  }

  func clearPlannerSession() {
    brief = ""
    storyboard = nil
    originalStoryboard = nil
    sceneEdits = []
    yamlPreview = ""
    preflight = nil
    bundleKey = nil
    renderJobId = nil
    renderStatus = ""
    audioKey = nil
    refineInstruction = ""
    plannerStep = .plan
    selectedProjectId = nil
    castSlots = plannerSlotIDs.map { PlanCastSlot(letter: $0) }
    persistSession()
  }

  func bootstrap() async {
    guard let client else {
      lastError = "Not configured"
      return
    }
    busy = true
    lastError = nil
    defer { busy = false }
    do {
      async let w = client.whoami()
      async let m = client.modules()
      async let p = client.listProjects()
      async let c = client.listCast()
      whoami = try await w
      modules = try await m
      projects = try await p
      cast = try await c
      await loadModels(client: client)
      qualityTier = modules?.defaultQualityTier ?? "final"
      statusMessage = "Connected as \(whoami?.user ?? whoami?.email ?? "studio")"
    } catch {
      lastError = error.localizedDescription
    }
  }

  private func loadModels(client: VivijureClient) async {
    if let models = try? await client.storyboardModels() {
      var ids: [String] = []
      for item in models.models ?? [] {
        if case .string(let s) = item {
          ids.append(s)
        } else if case .object(let o) = item {
          if let id = o["id"]?.stringValue ?? o["name"]?.stringValue {
            ids.append(id)
          }
        }
      }
      availableModels = ids
      if planModel.isEmpty {
        if let d = models.default_model, !d.isEmpty {
          planModel = d
        } else if let first = ids.first {
          planModel = first
        } else {
          planModel = "claude-sonnet-4-5"
        }
      }
    } else if planModel.isEmpty {
      planModel = "claude-sonnet-4-5"
    }
  }

  func refreshProjects() async {
    guard let client else { return }
    do { projects = try await client.listProjects() } catch { lastError = error.localizedDescription }
  }

  func refreshCast() async {
    guard let client else { return }
    do { cast = try await client.listCast() } catch { lastError = error.localizedDescription }
  }

  func refreshHistory() async {
    guard let client else { return }
    do { renders = try await client.listRenders(projectId: selectedProjectId) } catch {
      lastError = error.localizedDescription
    }
  }

  func selectProject(_ id: Int?) async {
    selectedProjectId = id
    guard let id, let client else {
      persistSession()
      return
    }
    do {
      let p = try await client.getProject(id: id)
      if let sb = p.last_storyboard {
        applyStoryboard(sb, resetOriginal: true)
        statusMessage = "Loaded project storyboard"
      }
      persistSession()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func deleteSelectedProject() async {
    guard let client, let id = selectedProjectId else { return }
    busy = true
    defer { busy = false }
    do {
      try await client.deleteProject(id: id)
      selectedProjectId = nil
      await refreshProjects()
      statusMessage = "Project deleted"
      persistSession()
    } catch {
      lastError = error.localizedDescription
    }
  }

  private func planCharactersJSON() -> JSONValue? {
    var chars: [JSONValue] = []
    for slot in castSlots where slot.included {
      if !slot.boundCastId.isEmpty, let m = cast.first(where: { $0.id == slot.boundCastId }) {
        chars.append(.object([
          "slot": .string(slot.letter),
          "name": .string(m.name),
          "bible": .string(m.bible ?? ""),
        ]))
      } else {
        let name = slot.inlineName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { continue }
        chars.append(.object([
          "slot": .string(slot.letter),
          "name": .string(name),
          "bible": .string(slot.inlineBible),
        ]))
      }
    }
    return chars.isEmpty ? nil : .array(chars)
  }

  func runPlan() async {
    guard let client else { return }
    busy = true
    lastError = nil
    defer { busy = false }
    do {
      let resp = try await client.plan(
        brief: brief,
        model: planModel.isEmpty ? nil : planModel,
        characters: planCharactersJSON()
      )
      if let err = resp.error {
        lastError = err
        return
      }
      guard let sb = resp.storyboard else {
        lastError = "Plan returned no storyboard"
        return
      }
      applyStoryboard(sb, resetOriginal: true)
      if let pid = selectedProjectId {
        _ = try await client.saveStoryboard(projectId: pid, storyboard: sb)
        await refreshProjects()
      }
      plannerStep = .castBundle
      statusMessage = "Plan ready (\(sceneEdits.count) scenes)"
      persistSession()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func runRefine() async {
    guard let client, let storyboard else { return }
    let instruction = refineInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !instruction.isEmpty else {
      lastError = "Refine instruction required"
      return
    }
    busy = true
    lastError = nil
    defer { busy = false }
    do {
      let resp = try await client.refine(
        storyboard: storyboard,
        instruction: instruction,
        model: planModel.isEmpty ? nil : planModel
      )
      if let err = resp.error {
        lastError = err
        return
      }
      guard let sb = resp.storyboard else {
        lastError = "Refine returned no storyboard"
        return
      }
      applyStoryboard(sb, resetOriginal: true)
      if let pid = selectedProjectId {
        _ = try await client.saveStoryboard(projectId: pid, storyboard: sb)
      }
      refineInstruction = ""
      statusMessage = "Refined (\(sceneEdits.count) scenes)"
      persistSession()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func applyStoryboard(_ sb: JSONValue, resetOriginal: Bool) {
    storyboard = sb
    if resetOriginal {
      originalStoryboard = sb
    }
    sceneEdits = SceneEdit.from(storyboard: sb)
    Task { await refreshYaml() }
  }

  func commitSceneEdits() {
    guard let storyboard else { return }
    let next = StoryboardMutator.applyScenes(sceneEdits, to: storyboard)
    applyStoryboard(next, resetOriginal: false)
    preflight = nil
    bundleKey = nil
    persistSession()
  }

  func deleteScene(at index: Int) {
    guard let storyboard else { return }
    let next = StoryboardMutator.deleteScene(at: index, from: storyboard)
    applyStoryboard(next, resetOriginal: false)
    preflight = nil
    bundleKey = nil
    persistSession()
  }

  func discardSceneEdits() {
    guard let originalStoryboard else { return }
    applyStoryboard(originalStoryboard, resetOriginal: true)
    statusMessage = "Discarded scene edits"
    persistSession()
  }

  func refreshYaml() async {
    guard let client, let storyboard else {
      yamlPreview = ""
      return
    }
    do {
      let r = try await client.storyboardYaml(storyboard: storyboard)
      if let yaml = r.yaml {
        yamlPreview = yaml
      } else {
        yamlPreview = r.error ?? "yaml validation failed"
      }
    } catch {
      yamlPreview = error.localizedDescription
    }
  }

  func saveStoryboardToProject() async {
    guard let client, let storyboard, let pid = selectedProjectId else {
      lastError = "Select a project to save"
      return
    }
    do {
      _ = try await client.saveStoryboard(projectId: pid, storyboard: storyboard)
      await refreshProjects()
      statusMessage = "Storyboard saved to project"
    } catch {
      lastError = error.localizedDescription
    }
  }

  func runPreflight() async {
    guard let client, let storyboard else { return }
    busy = true
    lastError = nil
    defer { busy = false }
    do {
      let bindings = castBindings.isEmpty ? nil : castBindings
      preflight = try await client.preflight(
        PreflightRequest(
          storyboard: storyboard,
          castBindings: bindings,
          quality: qualityTier
        )
      )
      statusMessage = preflight?.ok == true ? "Preflight OK" : "Preflight has issues"
    } catch {
      lastError = error.localizedDescription
    }
  }

  func runBundle() async {
    guard let client, let storyboard else { return }
    busy = true
    lastError = nil
    defer { busy = false }
    do {
      let useChars = StoryboardMutator.useCharacters(from: storyboard)
      var inline: [String: (name: String, bible: String)] = [:]
      for slot in castSlots where slot.included {
        let n = slot.inlineName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty {
          inline[slot.letter] = (n, slot.inlineBible)
        }
      }
      let refs: JSONValue
      if useChars.isEmpty {
        refs = .object([:])
      } else {
        refs = StoryboardMutator.characterRefs(
          useCharacters: useChars,
          castBindings: castBindings,
          cast: cast,
          inlineNames: inline
        )
        // Require at least one training image per used slot when slots are present.
        if case .object(let o) = refs {
          for slot in useChars {
            guard let entry = o[slot]?.objectValue,
                  let imgs = entry["trainingImages"]?.arrayValue,
                  !imgs.isEmpty
            else {
              lastError =
                "Slot \(slot) has no training images. Bind a cast member with portrait/refs, or upload in Cast tab."
              return
            }
          }
        }
      }
      let resp = try await client.bundle(storyboard: storyboard, characterRefs: refs)
      guard let key = resp.key else {
        lastError = resp.error ?? "Bundle returned no key"
        return
      }
      bundleKey = key
      plannerStep = .render
      statusMessage = "Bundled: \(key)"
      persistSession()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func runRender() async {
    guard let client, let storyboard else { return }
    busy = true
    lastError = nil
    defer { busy = false }
    do {
      let body = StoryboardRenderRequest(
        storyboard: storyboard,
        bundleKey: bundleKey,
        qualityTier: qualityTier,
        projectId: selectedProjectId,
        castLoras: nil,
        keyframesOnly: keyframesOnly ? true : nil
      )
      let job = try await client.submitStoryboardRender(body)
      guard let jid = job.resolvedJobId else {
        lastError = job.error ?? "No job id"
        return
      }
      renderJobId = jid
      renderStatus = job.status ?? job.phase ?? "submitted"
      plannerStep = .history
      statusMessage = "Render \(jid)"
      persistSession()
      await pollRenderLoop()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func pollRenderLoop() async {
    guard let client, let jid = renderJobId else { return }
    for _ in 0 ..< 120 {
      do {
        let job = try await client.pollStoryboardRender(jobId: jid)
        renderStatus = job.status ?? job.phase ?? renderStatus
        let done = ["COMPLETED", "FAILED", "CANCELLED", "done", "failed"].contains {
          ($0.caseInsensitiveCompare(renderStatus) == .orderedSame)
        }
        if done {
          statusMessage = "Render \(renderStatus)"
          await refreshHistory()
          persistSession()
          return
        }
      } catch {
        lastError = error.localizedDescription
        return
      }
      try? await Task.sleep(nanoseconds: 8_000_000_000)
    }
  }

  func snapScenesToBPM() {
    guard let storyboard else { return }
    let next = StoryboardMutator.snapScenesToBeats(
      storyboard: storyboard,
      bpm: bpm,
      beatsPerShot: beatsPerShot
    )
    applyStoryboard(next, resetOriginal: false)
    statusMessage = "Snapped scenes to \(bpm) BPM / \(beatsPerShot) beats"
    persistSession()
  }

  func analyzeCurrentAudio() async {
    guard let client, let key = audioKey else {
      lastError = "No audio key"
      return
    }
    busy = true
    defer { busy = false }
    do {
      let r = try await client.analyzeAudio(key: key)
      if case .object(let o) = r, let detected = o["bpm"]?.doubleValue {
        bpm = detected
        statusMessage = "Analyzed BPM \(detected)"
      } else {
        statusMessage = "Analyze: \(r.prettyJSON().prefix(200))"
      }
    } catch {
      lastError = error.localizedDescription
    }
  }

  func uploadAudioData(_ data: Data, mime: String) async {
    guard let client else { return }
    busy = true
    defer { busy = false }
    do {
      let up = try await client.uploadAudio(data: data, mime: mime)
      audioKey = up.key
      statusMessage = "Audio staged: \(up.key)"
      persistSession()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func createProject(name: String) async {
    guard let client else { return }
    do {
      let p = try await client.createProject(name: name)
      selectedProjectId = p.id
      await refreshProjects()
      persistSession()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func createCastMember(name: String, bible: String?) async {
    guard let client else { return }
    do {
      _ = try await client.createCast(name: name, bible: bible)
      await refreshCast()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func deleteCastMember(id: String) async {
    guard let client else { return }
    do {
      try await client.deleteCast(id: id)
      // Drop bindings pointing at deleted cast.
      for i in castSlots.indices where castSlots[i].boundCastId == id {
        castSlots[i].boundCastId = ""
      }
      await refreshCast()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func patchCastMember(id: String, name: String?, bible: String?, voiceId: String?) async {
    guard let client else { return }
    do {
      _ = try await client.patchCast(id: id, name: name, bible: bible, voiceId: voiceId)
      await refreshCast()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func uploadCastImage(id: String, kind: VivijureClient.CastMediaKind, data: Data, mime: String) async {
    guard let client else { return }
    busy = true
    defer { busy = false }
    do {
      _ = try await client.uploadCastImage(castId: id, kind: kind, data: data, mime: mime)
      await refreshCast()
      statusMessage = "Uploaded \(kind.rawValue)"
    } catch {
      lastError = error.localizedDescription
    }
  }

  func trainCastLora(id: String, wan: Bool) async {
    guard let client else { return }
    busy = true
    defer { busy = false }
    do {
      let r = wan
        ? try await client.trainWanLora(castId: id)
        : try await client.trainLora(castId: id)
      if let err = r.error {
        lastError = err
      } else {
        statusMessage = "Train \(wan ? "Wan" : "SDXL") job \(r.resolvedJobId ?? "?")"
      }
      await refreshCast()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func deleteRender(id: Int) async {
    guard let client else { return }
    do {
      try await client.deleteRender(id: id)
      await refreshHistory()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func patchRenderLabel(id: Int, label: String) async {
    guard let client else { return }
    do {
      _ = try await client.patchRender(id: id, label: label)
      await refreshHistory()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func openArtifact(key: String) async -> URL? {
    guard let client else { return nil }
    do {
      let r = try await client.artifactURL(key: key)
      guard let s = r.resolvedURL, let url = URL(string: s) else { return nil }
      return url
    } catch {
      lastError = error.localizedDescription
      return nil
    }
  }

  // MARK: - Session persistence (UserDefaults; token stays in Keychain)

  private struct SessionBlob: Codable {
    var brief: String?
    var planModel: String?
    var selectedProjectId: Int?
    var storyboard: JSONValue?
    var originalStoryboard: JSONValue?
    var bundleKey: String?
    var audioKey: String?
    var qualityTier: String?
    var renderJobId: String?
    var plannerStep: String?
    var bpm: Double?
    var slots: [SlotBlob]?
  }

  private struct SlotBlob: Codable {
    var letter: String
    var included: Bool
    var boundCastId: String
    var inlineName: String
    var inlineBible: String
  }

  func persistSession() {
    let slots = castSlots.map {
      SlotBlob(
        letter: $0.letter,
        included: $0.included,
        boundCastId: $0.boundCastId,
        inlineName: $0.inlineName,
        inlineBible: $0.inlineBible
      )
    }
    let blob = SessionBlob(
      brief: brief,
      planModel: planModel,
      selectedProjectId: selectedProjectId,
      storyboard: storyboard,
      originalStoryboard: originalStoryboard,
      bundleKey: bundleKey,
      audioKey: audioKey,
      qualityTier: qualityTier,
      renderJobId: renderJobId,
      plannerStep: plannerStep.rawValue,
      bpm: bpm,
      slots: slots
    )
    if let data = try? JSONEncoder().encode(blob) {
      UserDefaults.standard.set(data, forKey: sessionKey)
    }
  }

  private func restoreSession() {
    guard let data = UserDefaults.standard.data(forKey: sessionKey),
          let blob = try? JSONDecoder().decode(SessionBlob.self, from: data)
    else { return }
    brief = blob.brief ?? ""
    planModel = blob.planModel ?? ""
    selectedProjectId = blob.selectedProjectId
    storyboard = blob.storyboard
    originalStoryboard = blob.originalStoryboard
    if let sb = blob.storyboard {
      sceneEdits = SceneEdit.from(storyboard: sb)
    }
    bundleKey = blob.bundleKey
    audioKey = blob.audioKey
    qualityTier = blob.qualityTier ?? "final"
    renderJobId = blob.renderJobId
    if let step = blob.plannerStep, let s = PlannerStep(rawValue: step) {
      plannerStep = s
    }
    bpm = blob.bpm ?? 120
    if let slots = blob.slots {
      castSlots = plannerSlotIDs.map { letter in
        if let s = slots.first(where: { $0.letter == letter }) {
          return PlanCastSlot(
            letter: letter,
            included: s.included,
            boundCastId: s.boundCastId,
            inlineName: s.inlineName,
            inlineBible: s.inlineBible
          )
        }
        return PlanCastSlot(letter: letter)
      }
    }
  }
}
