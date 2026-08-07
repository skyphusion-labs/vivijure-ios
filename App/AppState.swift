import Foundation
import SwiftUI
import UserNotifications
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
  @Published var renderTags: [String] = []
  @Published var plannerStep: PlannerStep = .plan
  @Published var qualityTier: String = "final"
  @Published var keyframesOnly: Bool = false
  @Published var useScatter: Bool = false
  @Published var scatterShards: Int = 2
  @Published var motionBackend: String = ""
  @Published var audioKey: String?
  @Published var bpm: Double = 120
  @Published var beatsPerShot: Double = 4
  @Published var refineInstruction: String = ""
  @Published var castSlots: [PlanCastSlot] = plannerSlotIDs.map { PlanCastSlot(letter: $0) }
  /// sceneId -> staged character-ref key for start keyframes.
  @Published var sceneStartImages: [String: String] = [:]
  @Published var prefs: JSONValue?
  @Published var installedModules: [JSONValue] = []
  @Published var storageUsage: StorageUsageResponse?
  @Published var notificationsEnabled: Bool = false
  /// Composite key "module.field" -> value for schema-driven render overrides.
  @Published var renderFieldValues: [String: JSONValue] = [:]
  @Published var scorePrompt: String = ""
  @Published var cloudAnimateModel: String = ""
  @Published var demoAvailable: Bool?
  @Published var demoScenes: [JSONValue] = []
  @Published var demoJobId: String?
  @Published var demoStatus: String = ""
  @Published var busy: Bool = false

  private let urlKey = "studio_url"
  private let tokenKey = "studio_token"
  private let sessionKey = "planner_session_v1"
  private let notifyKey = "notify_on_render"

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
    notificationsEnabled = UserDefaults.standard.bool(forKey: notifyKey)
    restoreSession()
  }

  var motionBackends: [String] {
    StoryboardMutator.motionBackends(from: modules)
  }

  /// Cloud motion backends (non own-gpu) for animate-cloud model picker.
  var cloudMotionModels: [String] {
    motionBackends.filter { $0 != "own-gpu" && !$0.contains("own-gpu") }
  }

  var castLoras: [String: String] {
    castBindings
  }

  var renderConfigModules: [RenderConfigModule] {
    RenderConfigSchema.modules(from: modules)
  }

  var currentRenderOverrides: JSONValue? {
    let o = RenderConfigSchema.buildOverrides(
      motionBackend: keyframesOnly ? nil : (motionBackend.isEmpty ? nil : motionBackend),
      fieldValues: renderFieldValues
    )
    if case .object(let map) = o, map.isEmpty { return nil }
    // Always include motion_backend when set so collect matches web.
    return o
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
    sceneStartImages = [:]
    useScatter = false
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
      if motionBackend.isEmpty, motionBackends.count == 1, let first = motionBackends.first {
        // Match web: single backend gets an explicit default; 2+ require a pick.
        motionBackend = first
      }
      if cloudAnimateModel.isEmpty, let first = cloudMotionModels.first {
        cloudAnimateModel = first
      }
      seedRenderFieldDefaults()
      if let p = try? await client.getPrefs() {
        prefs = p
      }
      if let menu = try? await client.demoMenu() {
        demoAvailable = menu.available
        demoScenes = menu.scenes ?? []
      } else {
        demoAvailable = false
      }
      statusMessage = "Connected as \(whoami?.user ?? whoami?.email ?? "studio")"
    } catch {
      lastError = error.localizedDescription
    }
  }

  func seedRenderFieldDefaults() {
    for mod in renderConfigModules {
      for field in mod.fields {
        let id = field.id
        if renderFieldValues[id] == nil, let def = field.defaultValue {
          renderFieldValues[id] = def
        }
      }
    }
  }

  func setRenderField(_ field: RenderConfigField, value: JSONValue?) {
    if let value {
      renderFieldValues[field.id] = value
    } else {
      renderFieldValues.removeValue(forKey: field.id)
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
    do {
      async let list = client.listRenders(projectId: selectedProjectId)
      async let tags = client.listRenderTags()
      renders = try await list
      renderTags = (try? await tags) ?? renderTags
    } catch {
      lastError = error.localizedDescription
    }
  }

  func requestNotificationPermission() async {
    let center = UNUserNotificationCenter.current()
    do {
      let ok = try await center.requestAuthorization(options: [.alert, .sound, .badge])
      notificationsEnabled = ok
      UserDefaults.standard.set(ok, forKey: notifyKey)
    } catch {
      lastError = error.localizedDescription
    }
  }

  func setNotificationsEnabled(_ on: Bool) async {
    if on {
      await requestNotificationPermission()
    } else {
      notificationsEnabled = false
      UserDefaults.standard.set(false, forKey: notifyKey)
    }
  }

  private func notifyRenderFinished(jobId: String, status: String) {
    guard notificationsEnabled else { return }
    let content = UNMutableNotificationContent()
    content.title = "Vivijure render"
    content.body = "\(jobId): \(status)"
    content.sound = .default
    let req = UNNotificationRequest(
      identifier: "render-\(jobId)-\(UUID().uuidString)",
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(req)
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
      var starts: JSONValue?
      if !sceneStartImages.isEmpty {
        var map: [String: JSONValue] = [:]
        for (sid, key) in sceneStartImages {
          map[sid] = .object(["key": .string(key)])
        }
        starts = .object(map)
      }
      let resp = try await client.bundle(
        storyboard: storyboard,
        characterRefs: refs,
        sceneStartImages: starts
      )
      guard let key = resp.key else {
        lastError = resp.error ?? "Bundle returned no key"
        return
      }
      bundleKey = key
      plannerStep = .render
      statusMessage = "Bundled: \(key)"
        + (sceneStartImages.isEmpty ? "" : " (\(sceneStartImages.count) scene starts)")
      persistSession()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func stageSceneStart(sceneId: String, data: Data, mime: String) async {
    guard let client else { return }
    busy = true
    defer { busy = false }
    do {
      let up = try await client.uploadCharacterRef(data: data, mime: mime)
      sceneStartImages[sceneId] = up.key
      statusMessage = "Staged start keyframe for \(sceneId)"
      persistSession()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func clearSceneStart(sceneId: String) {
    sceneStartImages.removeValue(forKey: sceneId)
    persistSession()
  }

  func runRender() async {
    guard let client, let storyboard else { return }
    busy = true
    lastError = nil
    defer { busy = false }
    do {
      if useScatter {
        await runScatterRender(client: client, storyboard: storyboard)
        return
      }
      if !keyframesOnly, motionBackends.count > 1, motionBackend.isEmpty {
        lastError = "Pick a motion backend (required when multiple are installed)"
        return
      }
      let body = StoryboardRenderRequest(
        storyboard: storyboard,
        bundleKey: bundleKey,
        qualityTier: qualityTier,
        projectId: selectedProjectId,
        castLoras: castLoras.isEmpty ? nil : castLoras,
        keyframesOnly: keyframesOnly ? true : nil,
        motionBackend: keyframesOnly ? nil : (motionBackend.isEmpty ? nil : motionBackend),
        audioKey: audioKey,
        renderOverrides: currentRenderOverrides
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

  private func runScatterRender(client: VivijureClient, storyboard: JSONValue) async {
    guard let bundleKey else {
      lastError = "Scatter needs a bundleKey; run bundle first"
      return
    }
    let shotIds = StoryboardMutator.sceneIds(from: storyboard)
    guard shotIds.count >= 2 else {
      lastError = "Scatter requires >= 2 shots"
      return
    }
    if castLoras.isEmpty {
      lastError = "Scatter requires at least one bound cast (castLoras)"
      return
    }
    if motionBackend.isEmpty {
      lastError = "Scatter requires a motion.backend selection"
      return
    }
    if let pid = selectedProjectId {
      _ = try? await client.saveStoryboard(projectId: pid, storyboard: storyboard)
    }
    var shards = scatterShards
    if shards < 2 { shards = 2 }
    if shards > shotIds.count { shards = shotIds.count }
    do {
      let body = ScatterRenderRequest(
        bundleKey: bundleKey,
        shotIds: shotIds,
        shardCount: shards,
        qualityTier: qualityTier,
        castLoras: castLoras,
        audioKey: audioKey,
        projectId: selectedProjectId,
        motionBackend: motionBackend,
        renderOverrides: currentRenderOverrides
      )
      let job = try await client.submitScatterRender(body)
      guard let jid = job.resolvedJobId else {
        lastError = job.error ?? "No scatter job id"
        return
      }
      renderJobId = jid
      renderStatus = job.status ?? job.phase ?? "submitted"
      plannerStep = .history
      statusMessage = "Scatter \(jid) (\(shards) shards)"
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
          notifyRenderFinished(jobId: jid, status: renderStatus)
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

  /// Web "rerun bundle": load bundle + tier + optional storyboard from a history row.
  func loadRenderIntoPlanner(_ row: RenderRow) {
    if let key = row.bundle_key {
      bundleKey = key
    }
    if let tier = row.quality_tier, !tier.isEmpty {
      qualityTier = tier
    }
    if let pid = row.project_id {
      selectedProjectId = pid
    }
    if let sb = row.storyboard {
      applyStoryboard(sb, resetOriginal: true)
    }
    plannerStep = .render
    statusMessage = "Loaded bundle \(row.bundle_key ?? "?") from history"
    persistSession()
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

  func patchRenderTags(id: Int, tags: [String]) async {
    guard let client else { return }
    do {
      _ = try await client.patchRender(id: id, tags: tags)
      await refreshHistory()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func addAudioToHistory(id: Int) async {
    guard let client, let audioKey else {
      lastError = "Stage an audio bed first (Audio step)"
      return
    }
    busy = true
    defer { busy = false }
    do {
      _ = try await client.addAudioToRender(id: id, audioKey: audioKey)
      statusMessage = "Audio muxed onto render #\(id)"
      await refreshHistory()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func addNarrationToHistory(id: Int, text: String) async {
    guard let client else { return }
    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else {
      lastError = "Narration text required"
      return
    }
    busy = true
    defer { busy = false }
    do {
      _ = try await client.addNarrationToRender(id: id, text: t)
      statusMessage = "Narration added to #\(id)"
      await refreshHistory()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func finalizeHistory(id: Int) async {
    guard let client else { return }
    busy = true
    defer { busy = false }
    do {
      _ = try await client.finalizeRender(
        id: id,
        audioKey: audioKey,
        castLoras: castLoras.isEmpty ? nil : castLoras
      )
      statusMessage = "Finalize submitted for #\(id)"
      await refreshHistory()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func animateCloudHistory(id: Int) async {
    guard let client else { return }
    busy = true
    defer { busy = false }
    do {
      _ = try await client.animateCloud(
        id: id,
        model: cloudAnimateModel.isEmpty ? nil : cloudAnimateModel,
        audioKey: audioKey
      )
      statusMessage = "Cloud animate submitted for #\(id)"
      await refreshHistory()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func animateHybridHistory(id: Int, defaultBackend: String = "gpu") async {
    guard let client else { return }
    busy = true
    defer { busy = false }
    do {
      _ = try await client.animateHybrid(
        id: id,
        backends: nil,
        defaultBackend: defaultBackend,
        defaultCloudModel: cloudAnimateModel.isEmpty ? nil : cloudAnimateModel,
        audioKey: audioKey
      )
      statusMessage = "Hybrid animate submitted for #\(id)"
      await refreshHistory()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func setLockedShots(renderId: Int, shots: [String]) async {
    guard let client else { return }
    do {
      _ = try await client.patchRender(id: renderId, lockedShots: shots)
      await refreshHistory()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func toggleLockedShot(renderId: Int, shotId: String, currently: [String]) async {
    var next = Set(currently)
    if next.contains(shotId) {
      next.remove(shotId)
    } else {
      next.insert(shotId)
    }
    await setLockedShots(renderId: renderId, shots: Array(next).sorted())
  }

  func regenShot(renderId: Int, shotId: String) async {
    guard let client else { return }
    busy = true
    defer { busy = false }
    do {
      let job = try await client.regenShot(renderId: renderId, shotId: shotId)
      if let jid = job.resolvedJobId {
        statusMessage = "Regen \(shotId) job \(jid)"
        renderJobId = jid
        renderStatus = job.status ?? "submitted"
        await pollRenderLoop()
      } else {
        statusMessage = "Regen submitted for \(shotId)"
      }
      await refreshHistory()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func suggestScorePrompt(force: Bool = true) async {
    guard let storyboard else {
      lastError = "Plan a storyboard first"
      return
    }
    if !force, !scorePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return
    }
    // Prefer /api/chat when a plan model is set; fall back to local scaffold.
    if let client, !planModel.isEmpty {
      busy = true
      defer { busy = false }
      let scenes = storyboard.objectValue?["scenes"]?.arrayValue ?? []
      let arc = scenes.enumerated().map { i, s in
        let o = s.objectValue ?? [:]
        return "\(i + 1). [\(o["act"]?.stringValue ?? "?")] \(String((o["prompt"]?.stringValue ?? "").prefix(80)))"
      }.joined(separator: "\n")
      let dur = storyboard.objectValue?["duration_seconds"]?.doubleValue
        ?? Double(scenes.count) * (storyboard.objectValue?["clip_seconds"]?.doubleValue ?? 4)
      let instruction =
        "You are writing the single best text prompt for an AI music generator "
        + "to SCORE a short cinematic/anime video. Output ONE "
        + "concise INSTRUMENTAL music prompt only: 2 to 4 sentences, no preamble, no "
        + "quotes, do not address me. Describe the MUSIC ONLY (genre/style, tempo in "
        + "BPM if the material implies one, mood, the key instruments, and how the "
        + "energy should build and hit across roughly \(Int(dur)) seconds so it lands "
        + "with the on-screen action). Do not mention characters, the camera, or "
        + "visuals; translate them into musical terms.\n\n"
        + "Video concept: \(storyboard.objectValue?["full_prompt"]?.stringValue ?? "(none)")\n"
        + "Visual style: \(storyboard.objectValue?["style_prefix"]?.stringValue ?? "(none)")\n"
        + (brief.isEmpty ? "" : "Original brief: \(brief)\n")
        + "Shot arc (act + gist):\n\(arc.isEmpty ? "(none)" : arc)"
      do {
        let r = try await client.chat(model: planModel, userInput: instruction)
        if let out = r.output?.trimmingCharacters(in: .whitespacesAndNewlines), !out.isEmpty {
          scorePrompt = out
          statusMessage = "Score prompt suggested"
          return
        }
      } catch {
        // Fall through to scaffold.
        lastError = nil
      }
    }
    scorePrompt = RenderConfigSchema.scorePromptScaffold(storyboard: storyboard, brief: brief)
    statusMessage = "Score prompt scaffold (local)"
  }

  func runDemoRender(scene: String) async {
    guard let client else { return }
    busy = true
    defer { busy = false }
    do {
      let r = try await client.demoRender(scene: scene)
      guard let jid = r.resolvedJobId else {
        lastError = r.error ?? "No demo job id"
        return
      }
      demoJobId = jid
      demoStatus = r.status ?? "submitted"
      for _ in 0 ..< 60 {
        let poll = try await client.pollDemoRender(id: jid)
        if case .object(let o) = poll {
          demoStatus = o["status"]?.stringValue ?? demoStatus
          let st = demoStatus.lowercased()
          if ["completed", "failed", "done", "error"].contains(st) { break }
        }
        try? await Task.sleep(nanoseconds: 3_000_000_000)
      }
      statusMessage = "Demo \(demoStatus)"
    } catch {
      lastError = error.localizedDescription
    }
  }

  func runDemoChat(message: String) async -> String? {
    guard let client else { return nil }
    do {
      let r = try await client.demoChat(message: message)
      return r.reply ?? r.output
    } catch {
      lastError = error.localizedDescription
      return nil
    }
  }

  func generateCastRefs(id: String) async {
    guard let client else { return }
    busy = true
    defer { busy = false }
    do {
      let start = try await client.generateRefs(castId: id)
      guard case .object(let o) = start,
            let jid = o["job_id"]?.stringValue ?? o["jobId"]?.stringValue
      else {
        statusMessage = "generate-refs: \(start.prettyJSON().prefix(120))"
        await refreshCast()
        return
      }
      statusMessage = "refs job \(jid)"
      for _ in 0 ..< 60 {
        let job = try await client.pollRefsJob(castId: id, jobId: jid)
        if case .object(let jo) = job {
          let phase = jo["phase"]?.stringValue ?? ""
          statusMessage = "refs \(jid): \(phase)"
          if ["done", "failed"].contains(phase) { break }
        }
        try? await Task.sleep(nanoseconds: 3_000_000_000)
      }
      await refreshCast()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func exportCastData(id: String) async -> Data? {
    guard let client else { return nil }
    busy = true
    defer { busy = false }
    do {
      return try await client.exportCast(id: id)
    } catch {
      lastError = error.localizedDescription
      return nil
    }
  }

  func importCastTar(_ data: Data) async {
    guard let client else { return }
    busy = true
    defer { busy = false }
    do {
      let m = try await client.importCast(tarData: data)
      statusMessage = "Imported cast \(m.name)"
      await refreshCast()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func refreshInstalledModules() async {
    guard let client else { return }
    do {
      installedModules = try await client.listInstalledModules()
    } catch {
      // Hosts without MODULE_DISPATCH return 400; surface quietly.
      lastError = error.localizedDescription
    }
  }

  func installModule(scriptName: String) async {
    guard let client else { return }
    busy = true
    defer { busy = false }
    do {
      _ = try await client.installModule(scriptName: scriptName)
      await refreshInstalledModules()
      await bootstrap()
      statusMessage = "Installed \(scriptName)"
    } catch {
      lastError = error.localizedDescription
    }
  }

  func uninstallModule(name: String) async {
    guard let client else { return }
    busy = true
    defer { busy = false }
    do {
      try await client.uninstallModule(name: name)
      await refreshInstalledModules()
      await bootstrap()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func setModuleEnabled(name: String, enabled: Bool) async {
    guard let client else { return }
    do {
      _ = try await client.setModuleEnabled(name: name, enabled: enabled)
      await refreshInstalledModules()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func loadModuleConfig(name: String) async -> JSONValue? {
    guard let client else { return nil }
    do {
      let r = try await client.getModuleConfig(name: name)
      return r.config
    } catch {
      lastError = error.localizedDescription
      return nil
    }
  }

  func saveModuleConfig(name: String, config: JSONValue) async {
    guard let client else { return }
    busy = true
    defer { busy = false }
    do {
      _ = try await client.patchModuleConfig(name: name, config: config)
      statusMessage = "Saved config for \(name)"
    } catch {
      lastError = error.localizedDescription
    }
  }

  func savePrefs(_ next: JSONValue) async {
    guard let client else { return }
    do {
      prefs = try await client.patchPrefs(next)
      statusMessage = "Prefs saved"
    } catch {
      lastError = error.localizedDescription
    }
  }

  func refreshStorage() async {
    guard let client else { return }
    do {
      storageUsage = try await client.storageUsage()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func reconcileStorage() async {
    guard let client else { return }
    busy = true
    defer { busy = false }
    do {
      _ = try await client.storageReconcile()
      await refreshStorage()
      statusMessage = "Storage reconcile submitted"
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
    var sceneStartImages: [String: String]?
    var motionBackend: String?
    var keyframesOnly: Bool?
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
      slots: slots,
      sceneStartImages: sceneStartImages,
      motionBackend: motionBackend,
      keyframesOnly: keyframesOnly
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
    sceneStartImages = blob.sceneStartImages ?? [:]
    motionBackend = blob.motionBackend ?? ""
    keyframesOnly = blob.keyframesOnly ?? false
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
