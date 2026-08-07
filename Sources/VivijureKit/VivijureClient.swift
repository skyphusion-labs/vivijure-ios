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

  public func deleteCast(id: String) async throws {
    struct Ok: Decodable { var ok: Bool? }
    _ = try await http.sendJSON(
      Ok.self,
      method: "DELETE",
      path: "/api/cast/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)",
      bearer: token
    )
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

  public func bundle(storyboard: JSONValue, characterRefs: JSONValue) async throws -> BundleResponse {
    try await http.sendJSON(
      BundleResponse.self,
      method: "POST",
      path: "/api/storyboard/bundle",
      body: BundleRequest(storyboard: storyboard, characterRefs: characterRefs),
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

  public func listRenders(projectId: Int? = nil) async throws -> [RenderRow] {
    var q: [URLQueryItem] = []
    if let projectId { q.append(URLQueryItem(name: "project_id", value: String(projectId))) }
    let r: RendersListResponse = try await http.sendJSON(
      RendersListResponse.self,
      method: "GET",
      path: "/api/storyboard/renders",
      bearer: token,
      query: q
    )
    return r.renders
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
