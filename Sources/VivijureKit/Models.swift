import Foundation

// MARK: - Auth / identity

public struct WhoamiResponse: Codable, Sendable, Equatable {
  public var user: String?
  public var email: String?
  public var readonly: Bool?
}

// MARK: - Modules (registry projection; largely opaque)

public struct ModulesResponse: Codable, Sendable {
  public var modules: [JSONValue]?
  public var hooks: JSONValue?
  public var catalog: JSONValue?
  public var render: JSONValue?
  public var readonly: Bool?
  public var api: JSONValue?

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: DynamicKey.self)
    modules = try c.decodeIfPresent([JSONValue].self, forKey: DynamicKey("modules"))
    hooks = try c.decodeIfPresent(JSONValue.self, forKey: DynamicKey("hooks"))
    catalog = try c.decodeIfPresent(JSONValue.self, forKey: DynamicKey("catalog"))
    render = try c.decodeIfPresent(JSONValue.self, forKey: DynamicKey("render"))
    readonly = try c.decodeIfPresent(Bool.self, forKey: DynamicKey("readonly"))
    api = try c.decodeIfPresent(JSONValue.self, forKey: DynamicKey("api"))
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: DynamicKey.self)
    try c.encodeIfPresent(modules, forKey: DynamicKey("modules"))
    try c.encodeIfPresent(hooks, forKey: DynamicKey("hooks"))
    try c.encodeIfPresent(catalog, forKey: DynamicKey("catalog"))
    try c.encodeIfPresent(render, forKey: DynamicKey("render"))
    try c.encodeIfPresent(readonly, forKey: DynamicKey("readonly"))
    try c.encodeIfPresent(api, forKey: DynamicKey("api"))
  }

  /// Quality tier strings from `render.quality_tiers` when present.
  public var qualityTiers: [String] {
    guard let render,
          case .object(let o) = render,
          let tiers = o["quality_tiers"],
          case .array(let arr) = tiers
    else { return ["draft", "standard", "final"] }
    return arr.compactMap(\.stringValue)
  }

  public var defaultQualityTier: String {
    guard let render,
          case .object(let o) = render,
          let d = o["default_tier"]?.stringValue
    else { return qualityTiers.last ?? "final" }
    return d
  }
}

// MARK: - Projects

public struct StoryboardProject: Codable, Sendable, Identifiable, Equatable {
  public var id: Int
  public var slug: String?
  public var name: String
  public var prefs: JSONValue?
  public var last_storyboard: JSONValue?
  public var created_at: String?
  public var updated_at: String?
}

public struct ProjectsListResponse: Codable, Sendable {
  public var projects: [StoryboardProject]
}

public struct ProjectItemResponse: Codable, Sendable {
  public var project: StoryboardProject
}

// MARK: - Cast

public struct CastMember: Codable, Sendable, Identifiable, Equatable {
  public var id: String
  public var name: String
  public var bible: String?
  public var voice_id: String?
  public var portrait_key: String?
  public var portrait_mime: String?
  public var lora_status: String?
  /// CONTRACT: `{ key, mime }[]` training refs.
  public var ref_keys: [CastImageKey]?
  /// CONTRACT: source photos `{ key, mime }[]`.
  public var source_keys: [CastImageKey]?
  /// Legacy / alternate projections some hosts may still emit.
  public var refs: JSONValue?
  public var sources: JSONValue?

  public init(
    id: String,
    name: String,
    bible: String? = nil,
    voice_id: String? = nil,
    portrait_key: String? = nil,
    portrait_mime: String? = nil,
    lora_status: String? = nil,
    ref_keys: [CastImageKey]? = nil,
    source_keys: [CastImageKey]? = nil,
    refs: JSONValue? = nil,
    sources: JSONValue? = nil
  ) {
    self.id = id
    self.name = name
    self.bible = bible
    self.voice_id = voice_id
    self.portrait_key = portrait_key
    self.portrait_mime = portrait_mime
    self.lora_status = lora_status
    self.ref_keys = ref_keys
    self.source_keys = source_keys
    self.refs = refs
    self.sources = sources
  }
}

public struct CastImageKey: Codable, Sendable, Equatable {
  public var key: String
  public var mime: String?

  public init(key: String, mime: String? = nil) {
    self.key = key
    self.mime = mime
  }
}

public struct CastListResponse: Codable, Sendable {
  public var cast: [CastMember]
}

public struct CastItemResponse: Codable, Sendable {
  public var cast: CastMember
}

// MARK: - Plan / storyboard

public struct PlanRequest: Codable, Sendable {
  public var brief: String
  public var model: String?
  public var characters: JSONValue?

  public init(brief: String, model: String? = nil, characters: JSONValue? = nil) {
    self.brief = brief
    self.model = model
    self.characters = characters
  }
}

public struct PlanResponse: Codable, Sendable {
  public var ok: Bool?
  public var storyboard: JSONValue?
  public var error: String?
  public var errors: [JSONValue]?
  public var model: String?
}

public struct RefineRequest: Codable, Sendable {
  public var storyboard: JSONValue
  public var instruction: String
  public var model: String?

  public init(storyboard: JSONValue, instruction: String, model: String? = nil) {
    self.storyboard = storyboard
    self.instruction = instruction
    self.model = model
  }
}

public struct PreflightRequest: Codable, Sendable {
  public var storyboard: JSONValue
  public var castBindings: [String: String]?
  public var motionBackend: String?
  public var quality: String?

  public init(
    storyboard: JSONValue,
    castBindings: [String: String]? = nil,
    motionBackend: String? = nil,
    quality: String? = nil
  ) {
    self.storyboard = storyboard
    self.castBindings = castBindings
    self.motionBackend = motionBackend
    self.quality = quality
  }
}

public struct PreflightResponse: Codable, Sendable {
  public var ok: Bool
  public var counts: JSONValue?
  public var issues: [JSONValue]?
}

public struct BundleRequest: Codable, Sendable {
  public var storyboard: JSONValue
  public var characterRefs: JSONValue
  public var sceneStartImages: JSONValue?

  public init(
    storyboard: JSONValue,
    characterRefs: JSONValue,
    sceneStartImages: JSONValue? = nil
  ) {
    self.storyboard = storyboard
    self.characterRefs = characterRefs
    self.sceneStartImages = sceneStartImages
  }
}

public struct YamlResponse: Codable, Sendable {
  public var ok: Bool?
  public var yaml: String?
  public var error: String?
  public var errors: [JSONValue]?
}

public struct RenderPatchRequest: Codable, Sendable {
  public var label: String?
  public var tags: [String]?
  public var folderPath: String?

  public init(label: String? = nil, tags: [String]? = nil, folderPath: String? = nil) {
    self.label = label
    self.tags = tags
    self.folderPath = folderPath
  }
}

public struct TagsListResponse: Codable, Sendable {
  public var tags: [String]
}

public struct CastPatchRequest: Codable, Sendable {
  public var name: String?
  public var bible: String?
  public var voice_id: String?

  public init(name: String? = nil, bible: String? = nil, voiceId: String? = nil) {
    self.name = name
    self.bible = bible
    self.voice_id = voiceId
  }
}

public struct LoraStatusResponse: Codable, Sendable {
  public var cast: CastMember?
  public var view: JSONValue?
  public var ok: Bool?
  public var jobId: String?
  public var job_id: String?
  public var status: String?
  public var error: String?

  public var resolvedJobId: String? { jobId ?? job_id }
}

public struct BundleResponse: Codable, Sendable {
  public var bundleKey: String?
  public var bundle_key: String?
  public var ok: Bool?
  public var error: String?

  public var key: String? { bundleKey ?? bundle_key }
}

// MARK: - Render (web planner path)

public struct StoryboardRenderRequest: Codable, Sendable {
  public var storyboard: JSONValue?
  public var bundle_key: String?
  public var bundleKey: String?
  public var quality_tier: String?
  public var qualityTier: String?
  public var project: String?
  public var project_id: Int?
  public var cast_loras: [String: String]?
  public var keyframes_only: Bool?
  public var motion_backend: String?
  public var keyframe_backend: String?

  public init(
    storyboard: JSONValue? = nil,
    bundleKey: String? = nil,
    qualityTier: String? = nil,
    project: String? = nil,
    projectId: Int? = nil,
    castLoras: [String: String]? = nil,
    keyframesOnly: Bool? = nil,
    motionBackend: String? = nil,
    keyframeBackend: String? = nil
  ) {
    self.storyboard = storyboard
    self.bundle_key = bundleKey
    self.bundleKey = bundleKey
    self.quality_tier = qualityTier
    self.qualityTier = qualityTier
    self.project = project
    self.project_id = projectId
    self.cast_loras = castLoras
    self.keyframes_only = keyframesOnly
    self.motion_backend = motionBackend
    self.keyframe_backend = keyframeBackend
  }
}

public struct RenderJobResponse: Codable, Sendable {
  public var jobId: String?
  public var job_id: String?
  public var id: String?
  public var status: String?
  public var phase: String?
  public var error: String?
  public var output_key: String?
  public var download_url: String?
  public var ok: Bool?

  public var resolvedJobId: String? { jobId ?? job_id ?? id }
}

// MARK: - History

public struct RenderRow: Codable, Sendable, Identifiable, Equatable {
  public var id: Int
  public var job_id: String?
  public var project: String?
  public var bundle_key: String?
  public var quality_tier: String?
  public var status: String?
  public var output_key: String?
  public var error: String?
  public var label: String?
  public var mode: String?
  public var tags: [String]?
  public var project_id: Int?
}

public struct RendersListResponse: Codable, Sendable {
  public var renders: [RenderRow]
}

// MARK: - Upload / artifact

public struct UploadResponse: Codable, Sendable {
  public var key: String
  public var mime: String?
  public var size: Int?
}

public struct ArtifactURLResponse: Codable, Sendable {
  public var url: String?
  public var download_url: String?
  public var content_type: String?
  public var size: Int?

  public var resolvedURL: String? { url ?? download_url }
}

// MARK: - Models list

public struct StoryboardModelsResponse: Codable, Sendable {
  public var models: [JSONValue]?
  public var default_model: String?
}

// MARK: - Helpers

struct DynamicKey: CodingKey {
  var stringValue: String
  var intValue: Int? { nil }
  init(_ s: String) { stringValue = s }
  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
}

public extension StoryboardProject {
  /// Scene count from last_storyboard when shaped like a validated board.
  var sceneCount: Int? {
    guard let sb = last_storyboard?.objectValue,
          let scenes = sb["scenes"]?.arrayValue
    else { return nil }
    return scenes.count
  }
}
