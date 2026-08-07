import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Studio CONTRACT client (Bearer token). Matches web panel + vivijure-mcp route surface.
public struct VivijureClient: Sendable {
  public var baseURL: URL
  public var bearerToken: String?
  private let http: HTTPClient

  public init(baseURL: URL, bearerToken: String? = nil, session: URLSession? = nil) {
    self.baseURL = baseURL
    self.bearerToken = bearerToken
    self.http = HTTPClient(baseURL: baseURL, session: session)
  }

  public init(baseURLString: String, bearerToken: String? = nil) throws {
    guard let url = URL(string: baseURLString), url.scheme != nil else {
      throw VivijureError.invalidURL(baseURLString)
    }
    self.init(baseURL: url, bearerToken: bearerToken)
  }

  private var token: String {
    get throws {
      guard let t = bearerToken?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else {
        throw VivijureError.missingToken
      }
      return t
    }
  }

  // MARK: - Identity / registry

  public func whoami() async throws -> WhoamiResponse {
    try await http.sendJSON(WhoamiResponse.self, method: "GET", path: "/api/whoami", bearer: token)
  }

  public func modules() async throws -> ModulesResponse {
    try await http.sendJSON(ModulesResponse.self, method: "GET", path: "/api/modules", bearer: token)
  }

  public func storyboardModels() async throws -> StoryboardModelsResponse {
    try await http.sendJSON(
      StoryboardModelsResponse.self,
      method: "GET",
      path: "/api/storyboard/models",
      bearer: token
    )
  }

  public func voices() async throws -> JSONValue {
    try await http.sendJSON(JSONValue.self, method: "GET", path: "/api/voices", bearer: token)
  }

  // MARK: - Projects

  public func listProjects() async throws -> [StoryboardProject] {
    let r: ProjectsListResponse = try await http.sendJSON(
      ProjectsListResponse.self,
      method: "GET",
      path: "/api/storyboard/projects",
      bearer: token
    )
    return r.projects
  }

  public func getProject(id: Int) async throws -> StoryboardProject {
    let r: ProjectItemResponse = try await http.sendJSON(
      ProjectItemResponse.self,
      method: "GET",
      path: "/api/storyboard/projects/\(id)",
      bearer: token
    )
    return r.project
  }

  public func createProject(name: String, prefs: JSONValue? = nil) async throws -> StoryboardProject {
    struct Body: Encodable {
      var name: String
      var prefs: JSONValue?
    }
    let r: ProjectItemResponse = try await http.sendJSON(
      ProjectItemResponse.self,
      method: "POST",
      path: "/api/storyboard/projects",
      body: Body(name: name, prefs: prefs),
      bearer: token
    )
    return r.project
  }

  public func saveStoryboard(projectId: Int, storyboard: JSONValue) async throws -> StoryboardProject {
    struct Body: Encodable { var storyboard: JSONValue }
    let r: ProjectItemResponse = try await http.sendJSON(
      ProjectItemResponse.self,
      method: "POST",
      path: "/api/storyboard/projects/\(projectId)/storyboard",
      body: Body(storyboard: storyboard),
      bearer: token
    )
    return r.project
  }

  public func deleteProject(id: Int) async throws {
    struct Ok: Decodable { var ok: Bool? }
    _ = try await http.sendJSON(
      Ok.self,
      method: "DELETE",
      path: "/api/storyboard/projects/\(id)",
      bearer: token
    )
  }

  // MARK: - Cast

  public func listCast() async throws -> [CastMember] {
    let r: CastListResponse = try await http.sendJSON(
      CastListResponse.self,
      method: "GET",
      path: "/api/cast",
      bearer: token
    )
    return r.cast
  }

  public func getCast(id: String) async throws -> CastMember {
    let r: CastItemResponse = try await http.sendJSON(
      CastItemResponse.self,
      method: "GET",
      path: "/api/cast/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)",
      bearer: token
    )
    return r.cast
  }

  public func createCast(name: String, bible: String? = nil) async throws -> CastMember {
    struct Body: Encodable {
      var name: String
      var bible: String?
    }
    let r: CastItemResponse = try await http.sendJSON(
      CastItemResponse.self,
      method: "POST",
      path: "/api/cast",
      body: Body(name: name, bible: bible),
      bearer: token
    )
    return r.cast
  }

  public func patchCast(id: String, name: String? = nil, bible: String? = nil, voiceId: String? = nil) async throws -> CastMember {
    let enc = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    let r: CastItemResponse = try await http.sendJSON(
      CastItemResponse.self,
      method: "PATCH",
      path: "/api/cast/\(enc)",
      body: CastPatchRequest(name: name, bible: bible, voiceId: voiceId),
      bearer: token
    )
    return r.cast
  }

  public func deleteCast(id: String) async throws {
    struct Ok: Decodable { var ok: Bool? }
    let enc = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    _ = try await http.sendJSON(
      Ok.self,
      method: "DELETE",
      path: "/api/cast/\(enc)",
      bearer: token
    )
  }

  /// Form 1: raw image bytes to cast media routes (portrait / ref / source).
  public func uploadCastImage(
    castId: String,
    kind: CastMediaKind,
    data: Data,
    mime: String
  ) async throws -> CastMember {
    let enc = castId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? castId
    let path: String
    switch kind {
    case .portrait: path = "/api/cast/\(enc)/portrait"
    case .ref: path = "/api/cast/\(enc)/ref"
    case .source: path = "/api/cast/\(enc)/source"
    }
    let raw = try await http.sendRaw(
      method: "POST",
      path: path,
      body: data,
      contentType: mime,
      bearer: token
    )
    return try JSONDecoder().decode(CastItemResponse.self, from: raw).cast
  }

  public func deleteCastPortrait(id: String) async throws -> CastMember {
    let enc = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    let r: CastItemResponse = try await http.sendJSON(
      CastItemResponse.self,
      method: "DELETE",
      path: "/api/cast/\(enc)/portrait",
      bearer: token
    )
    return r.cast
  }

  public func deleteCastRef(id: String, key: String) async throws -> CastMember {
    struct Body: Encodable { var key: String }
    let enc = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    let r: CastItemResponse = try await http.sendJSON(
      CastItemResponse.self,
      method: "DELETE",
      path: "/api/cast/\(enc)/ref",
      body: Body(key: key),
      bearer: token
    )
    return r.cast
  }

  public func deleteCastSource(id: String, key: String) async throws -> CastMember {
    struct Body: Encodable { var key: String }
    let enc = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    let r: CastItemResponse = try await http.sendJSON(
      CastItemResponse.self,
      method: "DELETE",
      path: "/api/cast/\(enc)/source",
      body: Body(key: key),
      bearer: token
    )
    return r.cast
  }

  public func trainLora(castId: String) async throws -> LoraStatusResponse {
    let enc = castId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? castId
    return try await http.sendJSON(
      LoraStatusResponse.self,
      method: "POST",
      path: "/api/cast/\(enc)/train-lora",
      body: JSONValue.object([:]),
      bearer: token
    )
  }

  public func trainWanLora(castId: String) async throws -> LoraStatusResponse {
    let enc = castId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? castId
    return try await http.sendJSON(
      LoraStatusResponse.self,
      method: "POST",
      path: "/api/cast/\(enc)/train-wan-lora",
      body: JSONValue.object([:]),
      bearer: token
    )
  }

  public func loraStatus(castId: String) async throws -> LoraStatusResponse {
    let enc = castId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? castId
    return try await http.sendJSON(
      LoraStatusResponse.self,
      method: "GET",
      path: "/api/cast/\(enc)/lora-status",
      bearer: token
    )
  }

  public func generateRefs(castId: String, body: JSONValue = .object([:])) async throws -> JSONValue {
    let enc = castId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? castId
    return try await http.sendJSON(
      JSONValue.self,
      method: "POST",
      path: "/api/cast/\(enc)/generate-refs",
      body: body,
      bearer: token
    )
  }

  public func pollRefsJob(castId: String, jobId: String) async throws -> JSONValue {
    let c = castId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? castId
    let j = jobId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? jobId
    return try await http.sendJSON(
      JSONValue.self,
      method: "GET",
      path: "/api/cast/\(c)/refs-job/\(j)",
      bearer: token
    )
  }

  /// Export `.vvcast` tar bytes.
  public func exportCast(id: String) async throws -> Data {
    let enc = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    return try await http.sendBytes(
      method: "GET",
      path: "/api/cast/export/\(enc)",
      bearer: token
    )
  }

  /// Import raw `.vvcast` tar body.
  public func importCast(tarData: Data) async throws -> CastMember {
    let raw = try await http.sendBytes(
      method: "POST",
      path: "/api/cast/import",
      body: tarData,
      contentType: "application/x-tar",
      bearer: token
    )
    return try JSONDecoder().decode(CastItemResponse.self, from: raw).cast
  }

  public enum CastMediaKind: String, Sendable {
    case portrait
    case ref
    case source
  }

  // MARK: - Plan / preflight / bundle

  public func plan(brief: String, model: String?, characters: JSONValue? = nil) async throws -> PlanResponse {
    try await http.sendJSON(
      PlanResponse.self,
      method: "POST",
      path: "/api/storyboard/plan",
      body: PlanRequest(brief: brief, model: model, characters: characters),
      bearer: token
    )
  }

  public func refine(storyboard: JSONValue, instruction: String, model: String? = nil) async throws -> PlanResponse {
    try await http.sendJSON(
      PlanResponse.self,
      method: "POST",
      path: "/api/storyboard/refine",
      body: RefineRequest(storyboard: storyboard, instruction: instruction, model: model),
      bearer: token
    )
  }

  public func preflight(_ body: PreflightRequest) async throws -> PreflightResponse {
    try await http.sendJSON(
      PreflightResponse.self,
      method: "POST",
      path: "/api/storyboard/preflight",
      body: body,
      bearer: token
    )
  }

  public func bundle(
    storyboard: JSONValue,
    characterRefs: JSONValue,
    sceneStartImages: JSONValue? = nil
  ) async throws -> BundleResponse {
    try await http.sendJSON(
      BundleResponse.self,
      method: "POST",
      path: "/api/storyboard/bundle",
      body: BundleRequest(
        storyboard: storyboard,
        characterRefs: characterRefs,
        sceneStartImages: sceneStartImages
      ),
      bearer: token
    )
  }

  public func storyboardYaml(storyboard: JSONValue) async throws -> YamlResponse {
    struct Body: Encodable { var storyboard: JSONValue }
    return try await http.sendJSON(
      YamlResponse.self,
      method: "POST",
      path: "/api/storyboard/yaml",
      body: Body(storyboard: storyboard),
      bearer: token
    )
  }

  // MARK: - Render (web planner doors)

  public func submitStoryboardRender(_ body: StoryboardRenderRequest) async throws -> RenderJobResponse {
    try await http.sendJSON(
      RenderJobResponse.self,
      method: "POST",
      path: "/api/storyboard/render",
      body: body,
      bearer: token
    )
  }

  public func pollStoryboardRender(jobId: String) async throws -> RenderJobResponse {
    let enc = jobId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? jobId
    return try await http.sendJSON(
      RenderJobResponse.self,
      method: "GET",
      path: "/api/storyboard/render/\(enc)",
      bearer: token
    )
  }

  public func submitFilm(bundleKey: String, scenes: JSONValue, extra: [String: JSONValue] = [:]) async throws -> RenderJobResponse {
    var obj: [String: JSONValue] = [
      "bundle_key": .string(bundleKey),
      "scenes": scenes,
    ]
    for (k, v) in extra { obj[k] = v }
    return try await http.sendJSON(
      RenderJobResponse.self,
      method: "POST",
      path: "/api/render/film",
      body: JSONValue.object(obj),
      bearer: token
    )
  }

  public func pollFilm(id: String) async throws -> RenderJobResponse {
    let enc = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    return try await http.sendJSON(
      RenderJobResponse.self,
      method: "GET",
      path: "/api/render/film/\(enc)",
      bearer: token
    )
  }

  // MARK: - History / artifacts / upload

  public func listRenders(projectId: Int? = nil, limit: Int? = nil) async throws -> [RenderRow] {
    var q: [URLQueryItem] = []
    if let projectId { q.append(URLQueryItem(name: "project_id", value: String(projectId))) }
    if let limit { q.append(URLQueryItem(name: "limit", value: String(limit))) }
    let r: RendersListResponse = try await http.sendJSON(
      RendersListResponse.self,
      method: "GET",
      path: "/api/storyboard/renders",
      bearer: token,
      query: q
    )
    return r.renders
  }

  public func listRenderTags() async throws -> [String] {
    let r: TagsListResponse = try await http.sendJSON(
      TagsListResponse.self,
      method: "GET",
      path: "/api/storyboard/renders/tags",
      bearer: token
    )
    return r.tags
  }

  public func patchRender(
    id: Int,
    label: String? = nil,
    tags: [String]? = nil,
    folderPath: String? = nil,
    lockedShots: [String]? = nil
  ) async throws -> RenderRow {
    try await http.sendJSON(
      RenderRow.self,
      method: "PATCH",
      path: "/api/storyboard/renders/\(id)",
      body: RenderPatchRequest(
        label: label,
        tags: tags,
        folderPath: folderPath,
        lockedShots: lockedShots
      ),
      bearer: token
    )
  }

  public func regenShot(renderId: Int, shotId: String) async throws -> RenderJobResponse {
    struct Body: Encodable { var shotId: String }
    return try await http.sendJSON(
      RenderJobResponse.self,
      method: "POST",
      path: "/api/storyboard/renders/\(renderId)/regen-shot",
      body: Body(shotId: shotId),
      bearer: token
    )
  }

  public func deleteRender(id: Int) async throws {
    struct Ok: Decodable { var ok: Bool? }
    _ = try await http.sendJSON(
      Ok.self,
      method: "DELETE",
      path: "/api/storyboard/renders/\(id)",
      bearer: token
    )
  }

  public func addAudioToRender(id: Int, audioKey: String) async throws -> JSONValue {
    struct Body: Encodable { var audioKey: String }
    return try await http.sendJSON(
      JSONValue.self,
      method: "POST",
      path: "/api/storyboard/renders/\(id)/add-audio",
      body: Body(audioKey: audioKey),
      bearer: token
    )
  }

  public func addNarrationToRender(id: Int, text: String, module: String? = nil) async throws -> JSONValue {
    try await http.sendJSON(
      JSONValue.self,
      method: "POST",
      path: "/api/storyboard/renders/\(id)/add-narration",
      body: NarrationRequest(text: text, module: module),
      bearer: token
    )
  }

  public func finalizeRender(id: Int, audioKey: String? = nil, castLoras: [String: String]? = nil) async throws -> JSONValue {
    var obj: [String: JSONValue] = [:]
    if let audioKey { obj["audioKey"] = .string(audioKey) }
    if let castLoras {
      obj["castLoras"] = .object(castLoras.mapValues { .string($0) })
    }
    return try await http.sendJSON(
      JSONValue.self,
      method: "POST",
      path: "/api/storyboard/renders/\(id)/finalize",
      body: JSONValue.object(obj),
      bearer: token
    )
  }

  public func animateCloud(id: Int, model: String? = nil, audioKey: String? = nil) async throws -> JSONValue {
    var obj: [String: JSONValue] = [:]
    if let model { obj["model"] = .string(model) }
    if let audioKey { obj["audioKey"] = .string(audioKey) }
    return try await http.sendJSON(
      JSONValue.self,
      method: "POST",
      path: "/api/storyboard/renders/\(id)/animate-cloud",
      body: JSONValue.object(obj),
      bearer: token
    )
  }

  public func animateHybrid(
    id: Int,
    backends: JSONValue? = nil,
    defaultBackend: String? = "gpu",
    defaultCloudModel: String? = nil,
    audioKey: String? = nil
  ) async throws -> JSONValue {
    var obj: [String: JSONValue] = [:]
    if let backends { obj["backends"] = backends }
    if let defaultBackend { obj["defaultBackend"] = .string(defaultBackend) }
    if let defaultCloudModel { obj["defaultCloudModel"] = .string(defaultCloudModel) }
    if let audioKey { obj["audioKey"] = .string(audioKey) }
    return try await http.sendJSON(
      JSONValue.self,
      method: "POST",
      path: "/api/storyboard/renders/\(id)/animate-hybrid",
      body: JSONValue.object(obj),
      bearer: token
    )
  }

  public func chat(model: String, userInput: String) async throws -> ChatResponse {
    try await http.sendJSON(
      ChatResponse.self,
      method: "POST",
      path: "/api/chat",
      body: ChatRequest(model: model, userInput: userInput),
      bearer: token
    )
  }

  public func demoMenu() async throws -> DemoMenuResponse {
    try await http.sendJSON(
      DemoMenuResponse.self,
      method: "GET",
      path: "/api/demo/menu",
      bearer: token
    )
  }

  public func demoRender(scene: String) async throws -> DemoRenderResponse {
    struct Body: Encodable { var scene: String }
    return try await http.sendJSON(
      DemoRenderResponse.self,
      method: "POST",
      path: "/api/demo/render",
      body: Body(scene: scene),
      bearer: token
    )
  }

  public func pollDemoRender(id: String) async throws -> JSONValue {
    let enc = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    return try await http.sendJSON(
      JSONValue.self,
      method: "GET",
      path: "/api/demo/render/\(enc)",
      bearer: token
    )
  }

  public func demoChat(message: String) async throws -> ChatResponse {
    struct Body: Encodable { var message: String }
    return try await http.sendJSON(
      ChatResponse.self,
      method: "POST",
      path: "/api/demo/chat",
      body: Body(message: message),
      bearer: token
    )
  }

  public func submitScatterRender(_ body: ScatterRenderRequest) async throws -> RenderJobResponse {
    try await http.sendJSON(
      RenderJobResponse.self,
      method: "POST",
      path: "/api/storyboard/render/scatter",
      body: body,
      bearer: token
    )
  }

  public func getPrefs() async throws -> JSONValue {
    let r: PrefsResponse = try await http.sendJSON(
      PrefsResponse.self,
      method: "GET",
      path: "/api/prefs",
      bearer: token
    )
    return r.prefs ?? .object([:])
  }

  public func patchPrefs(_ prefs: JSONValue) async throws -> JSONValue {
    let r: PrefsResponse = try await http.sendJSON(
      PrefsResponse.self,
      method: "PATCH",
      path: "/api/prefs",
      body: prefs,
      bearer: token
    )
    return r.prefs ?? .object([:])
  }

  public func listInstalledModules() async throws -> [JSONValue] {
    let r: InstalledModulesResponse = try await http.sendJSON(
      InstalledModulesResponse.self,
      method: "GET",
      path: "/api/modules/installed",
      bearer: token
    )
    return r.modules ?? []
  }

  public func installModule(scriptName: String) async throws -> JSONValue {
    struct Body: Encodable { var script_name: String }
    return try await http.sendJSON(
      JSONValue.self,
      method: "POST",
      path: "/api/modules/install",
      body: Body(script_name: scriptName),
      bearer: token
    )
  }

  public func uninstallModule(name: String) async throws {
    let enc = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
    struct Ok: Decodable { var ok: Bool? }
    _ = try await http.sendJSON(
      Ok.self,
      method: "DELETE",
      path: "/api/modules/install/\(enc)",
      bearer: token
    )
  }

  public func setModuleEnabled(name: String, enabled: Bool) async throws -> JSONValue {
    struct Body: Encodable { var enabled: Bool }
    let enc = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
    return try await http.sendJSON(
      JSONValue.self,
      method: "PATCH",
      path: "/api/modules/install/\(enc)",
      body: Body(enabled: enabled),
      bearer: token
    )
  }

  public func getModuleConfig(name: String) async throws -> ModuleConfigResponse {
    let enc = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
    return try await http.sendJSON(
      ModuleConfigResponse.self,
      method: "GET",
      path: "/api/modules/\(enc)/config",
      bearer: token
    )
  }

  public func patchModuleConfig(name: String, config: JSONValue) async throws -> ModuleConfigResponse {
    let enc = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
    return try await http.sendJSON(
      ModuleConfigResponse.self,
      method: "PATCH",
      path: "/api/modules/\(enc)/config",
      body: config,
      bearer: token
    )
  }

  public func storageUsage() async throws -> StorageUsageResponse {
    try await http.sendJSON(
      StorageUsageResponse.self,
      method: "GET",
      path: "/api/storage/usage",
      bearer: token
    )
  }

  public func storageReconcile() async throws -> JSONValue {
    try await http.sendJSON(
      JSONValue.self,
      method: "POST",
      path: "/api/storage/reconcile",
      body: JSONValue.object([:]),
      bearer: token
    )
  }

  /// Stage an image under `character-refs/` (bundle scene starts / slot refs).
  public func uploadCharacterRef(data: Data, mime: String) async throws -> UploadResponse {
    let raw = try await http.sendRaw(
      method: "POST",
      path: "/api/storyboard/character-ref",
      body: data,
      contentType: mime,
      bearer: token
    )
    return try JSONDecoder().decode(UploadResponse.self, from: raw)
  }

  public func uploadImage(data: Data, mime: String) async throws -> UploadResponse {
    let raw = try await http.sendRaw(
      method: "POST",
      path: "/api/upload",
      body: data,
      contentType: mime,
      bearer: token
    )
    return try JSONDecoder().decode(UploadResponse.self, from: raw)
  }

  public func uploadAudio(data: Data, mime: String) async throws -> UploadResponse {
    let raw = try await http.sendRaw(
      method: "POST",
      path: "/api/storyboard/audio-upload",
      body: data,
      contentType: mime,
      bearer: token
    )
    return try JSONDecoder().decode(UploadResponse.self, from: raw)
  }

  public func artifactURL(key: String, expiresIn: Int = 300) async throws -> ArtifactURLResponse {
    let pathKey = key.split(separator: "/").map {
      String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
    }.joined(separator: "/")
    return try await http.sendJSON(
      ArtifactURLResponse.self,
      method: "GET",
      path: "/api/artifact-url/\(pathKey)",
      bearer: token,
      query: [URLQueryItem(name: "expires_in", value: String(expiresIn))]
    )
  }

  public func scoreBed(body: JSONValue) async throws -> JSONValue {
    try await http.sendJSON(
      JSONValue.self,
      method: "POST",
      path: "/api/storyboard/score-bed",
      body: body,
      bearer: token
    )
  }

  public func pollJob(id: String) async throws -> JSONValue {
    let enc = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    return try await http.sendJSON(
      JSONValue.self,
      method: "GET",
      path: "/api/job/\(enc)",
      bearer: token
    )
  }

  public func analyzeAudio(key: String) async throws -> JSONValue {
    struct Body: Encodable { var key: String }
    return try await http.sendJSON(
      JSONValue.self,
      method: "POST",
      path: "/api/audio/analyze",
      body: Body(key: key),
      bearer: token
    )
  }
}
