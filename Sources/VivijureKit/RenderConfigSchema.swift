import Foundation

/// One render-scope config field from a module's `config_schema` (CONTRACT 4.1).
public struct RenderConfigField: Identifiable, Equatable, Sendable {
  public var id: String { "\(moduleName).\(key)" }
  public var moduleName: String
  public var key: String
  public var type: String
  public var label: String
  public var defaultValue: JSONValue?
  public var min: Double?
  public var max: Double?
  public var enumValues: [String]
  public var enumLabels: [String: String]
  public var scope: String

  public init(
    moduleName: String,
    key: String,
    type: String,
    label: String,
    defaultValue: JSONValue? = nil,
    min: Double? = nil,
    max: Double? = nil,
    enumValues: [String] = [],
    enumLabels: [String: String] = [:],
    scope: String = "render"
  ) {
    self.moduleName = moduleName
    self.key = key
    self.type = type
    self.label = label
    self.defaultValue = defaultValue
    self.min = min
    self.max = max
    self.enumValues = enumValues
    self.enumLabels = enumLabels
    self.scope = scope
  }
}

/// Module group for the render config panel (web planner-render-config.js).
public struct RenderConfigModule: Identifiable, Equatable, Sendable {
  public var id: String { name }
  public var name: String
  public var label: String
  public var hooks: [String]
  public var fields: [RenderConfigField]

  public init(name: String, label: String, hooks: [String], fields: [RenderConfigField]) {
    self.name = name
    self.label = label
    self.hooks = hooks
    self.fields = fields
  }
}

public enum RenderConfigSchema {
  /// Hooks projected on bespoke surfaces (not the render config panel).
  public static let panelSkipHooks: Set<String> = [
    "plan.enhance", "score", "dialogue", "cast.image", "notify",
  ]

  /// Build render-scope fields from GET /api/modules, skipping install-scope + quality_tier.
  public static func modules(from response: ModulesResponse?) -> [RenderConfigModule] {
    guard let mods = response?.modules else { return [] }
    var out: [RenderConfigModule] = []
    for mod in mods {
      guard let o = mod.objectValue, let name = o["name"]?.stringValue else { continue }
      let hooks = moduleHooks(o)
      // Include if it provides any non-skipped hook OR has a config_schema with render fields.
      let relevantHooks = hooks.filter { !panelSkipHooks.contains($0) }
      guard let schema = o["config_schema"]?.objectValue, !schema.isEmpty else {
        if !relevantHooks.isEmpty {
          // Still list module with no knobs so choosers can reference it.
          out.append(RenderConfigModule(name: name, label: moduleLabel(o, name: name), hooks: relevantHooks, fields: []))
        }
        continue
      }
      var fields: [RenderConfigField] = []
      for (key, fieldVal) in schema.sorted(by: { $0.key < $1.key }) {
        guard let f = fieldVal.objectValue else { continue }
        let scope = f["scope"]?.stringValue ?? "render"
        if scope == "install" { continue }
        if key == "quality_tier" || key == "quality" { continue }
        let type = f["type"]?.stringValue ?? "string"
        let label = f["label"]?.stringValue ?? key
        var enumValues: [String] = []
        if let vals = f["values"]?.arrayValue {
          enumValues = vals.compactMap(\.stringValue)
        }
        var enumLabels: [String: String] = [:]
        if let el = f["enum_labels"]?.objectValue {
          for (k, v) in el {
            if let s = v.stringValue { enumLabels[k] = s }
          }
        }
        fields.append(
          RenderConfigField(
            moduleName: name,
            key: key,
            type: type,
            label: label,
            defaultValue: f["default"],
            min: f["min"]?.doubleValue,
            max: f["max"]?.doubleValue,
            enumValues: enumValues,
            enumLabels: enumLabels,
            scope: scope
          )
        )
      }
      if fields.isEmpty, relevantHooks.isEmpty { continue }
      out.append(
        RenderConfigModule(
          name: name,
          label: moduleLabel(o, name: name),
          hooks: relevantHooks.isEmpty ? hooks : relevantHooks,
          fields: fields
        )
      )
    }
    return out.sorted { $0.name < $1.name }
  }

  /// Wire form: `{ motion_backend?, config: { [module]: { knobs } } }`.
  public static func buildOverrides(
    motionBackend: String?,
    fieldValues: [String: JSONValue]
  ) -> JSONValue {
    var config: [String: JSONValue] = [:]
    for (composite, value) in fieldValues {
      // composite = "moduleName.key"
      guard let dot = composite.firstIndex(of: ".") else { continue }
      let mod = String(composite[..<dot])
      let key = String(composite[composite.index(after: dot)...])
      var bucket = config[mod]?.objectValue ?? [:]
      bucket[key] = value
      config[mod] = .object(bucket)
    }
    var out: [String: JSONValue] = [:]
    if !config.isEmpty {
      out["config"] = .object(config)
    }
    if let motionBackend, !motionBackend.isEmpty {
      out["motion_backend"] = .string(motionBackend)
    }
    return .object(out)
  }

  /// Local score-prompt scaffold (when chat is unavailable); mirrors the instruction inputs.
  public static func scorePromptScaffold(storyboard: JSONValue, brief: String) -> String {
    let o = storyboard.objectValue ?? [:]
    let scenes = o["scenes"]?.arrayValue ?? []
    let style = o["style_prefix"]?.stringValue ?? ""
    let concept = o["full_prompt"]?.stringValue ?? ""
    let dur = o["duration_seconds"]?.doubleValue
      ?? Double(scenes.count) * (o["clip_seconds"]?.doubleValue ?? 4)
    let arc = scenes.enumerated().prefix(8).map { i, s in
      let so = s.objectValue ?? [:]
      let act = so["act"]?.stringValue ?? "?"
      let p = (so["prompt"]?.stringValue ?? "").prefix(60)
      return "\(i + 1). [\(act)] \(p)"
    }.joined(separator: "; ")
    var parts: [String] = [
      "Instrumental cinematic underscore, roughly \(Int(dur)) seconds.",
    ]
    if !style.isEmpty { parts.append("Style mood: \(style).") }
    if !concept.isEmpty { parts.append("Concept energy: \(concept.prefix(120)).") }
    if !brief.isEmpty { parts.append("Brief: \(brief.prefix(120)).") }
    if !arc.isEmpty { parts.append("Arc: \(arc).") }
    parts.append("Build energy with the shot progression; no vocals.")
    return parts.joined(separator: " ")
  }

  private static func moduleLabel(_ o: [String: JSONValue], name: String) -> String {
    if let provides = o["provides"]?.arrayValue,
       let first = provides.first?.objectValue?["label"]?.stringValue,
       !first.isEmpty
    {
      return first
    }
    return name
  }

  private static func moduleHooks(_ o: [String: JSONValue]) -> [String] {
    if let provides = o["provides"]?.arrayValue {
      let ids = provides.compactMap { $0.objectValue?["id"]?.stringValue ?? $0.stringValue }
      if !ids.isEmpty { return ids }
    }
    if let hooks = o["hooks"]?.arrayValue {
      return hooks.compactMap(\.stringValue)
    }
    return []
  }
}
