import Foundation

/// Planner slot ids used by the web panel (`SLOT_IDS` in planner-stepper.js).
public let plannerSlotIDs: [String] = ["A", "B", "C", "D"]

/// Mutable view of one storyboard scene for the scene editor UI.
public struct SceneEdit: Identifiable, Equatable, Sendable {
  public var index: Int
  public var id: String
  public var prompt: String
  public var targetSeconds: Double?
  public var act: String
  public var characterSlots: [String]
  public var dialogueSlot: String
  public var dialogueText: String

  public init(
    index: Int,
    id: String,
    prompt: String,
    targetSeconds: Double? = nil,
    act: String = "",
    characterSlots: [String] = [],
    dialogueSlot: String = "",
    dialogueText: String = ""
  ) {
    self.index = index
    self.id = id
    self.prompt = prompt
    self.targetSeconds = targetSeconds
    self.act = act
    self.characterSlots = characterSlots
    self.dialogueSlot = dialogueSlot
    self.dialogueText = dialogueText
  }

  public static func from(storyboard: JSONValue) -> [SceneEdit] {
    guard let scenes = storyboard.objectValue?["scenes"]?.arrayValue else { return [] }
    return scenes.enumerated().map { idx, scene in
      let o = scene.objectValue ?? [:]
      let dlg = o["dialogue"]?.objectValue
      let slots: [String]
      if let arr = o["character_slots"]?.arrayValue {
        slots = arr.compactMap(\.stringValue)
      } else {
        slots = []
      }
      return SceneEdit(
        index: idx,
        id: o["id"]?.stringValue ?? "scene \(idx + 1)",
        prompt: o["prompt"]?.stringValue ?? "",
        targetSeconds: o["target_seconds"]?.doubleValue ?? o["clip_seconds"]?.doubleValue,
        act: o["act"]?.stringValue ?? "",
        characterSlots: slots,
        dialogueSlot: dlg?["slot"]?.stringValue ?? "",
        dialogueText: dlg?["text"]?.stringValue ?? ""
      )
    }
  }
}

public enum StoryboardMutator {
  /// Replace scenes array after UI edits. Returns nil if no scenes key.
  public static func applyScenes(_ edits: [SceneEdit], to storyboard: JSONValue) -> JSONValue {
    var root = storyboard.objectValue ?? [:]
    var scenes = root["scenes"]?.arrayValue ?? []
    for edit in edits {
      guard edit.index >= 0, edit.index < scenes.count else { continue }
      var o = scenes[edit.index].objectValue ?? [:]
      o["prompt"] = .string(edit.prompt)
      if let s = edit.targetSeconds {
        o["target_seconds"] = .number(s)
      } else {
        o.removeValue(forKey: "target_seconds")
      }
      let act = edit.act.trimmingCharacters(in: .whitespacesAndNewlines)
      if act.isEmpty {
        o.removeValue(forKey: "act")
      } else {
        o["act"] = .string(act)
      }
      if edit.characterSlots.isEmpty {
        o.removeValue(forKey: "character_slots")
      } else {
        o["character_slots"] = .array(edit.characterSlots.map { .string($0) })
      }
      let text = edit.dialogueText.trimmingCharacters(in: .whitespacesAndNewlines)
      let slot = edit.dialogueSlot.trimmingCharacters(in: .whitespacesAndNewlines)
      if text.isEmpty || slot.isEmpty {
        o.removeValue(forKey: "dialogue")
      } else {
        o["dialogue"] = .object([
          "slot": .string(slot),
          "text": .string(text),
        ])
      }
      scenes[edit.index] = .object(o)
    }
    root["scenes"] = .array(scenes)
    return .object(root)
  }

  public static func deleteScene(at index: Int, from storyboard: JSONValue) -> JSONValue {
    var root = storyboard.objectValue ?? [:]
    var scenes = root["scenes"]?.arrayValue ?? []
    guard index >= 0, index < scenes.count else { return storyboard }
    scenes.remove(at: index)
    root["scenes"] = .array(scenes)
    return .object(root)
  }

  public static func useCharacters(from storyboard: JSONValue) -> [String] {
    guard let arr = storyboard.objectValue?["use_characters"]?.arrayValue else { return [] }
    return arr.compactMap(\.stringValue)
  }

  /// Snap each scene's `target_seconds` to a musical phrase (web `snapToBeats`).
  public static func snapScenesToBeats(
    storyboard: JSONValue,
    bpm: Double,
    beatsPerShot: Double = 4
  ) -> JSONValue {
    guard bpm > 0, beatsPerShot > 0 else { return storyboard }
    let phrase = (60.0 / bpm) * beatsPerShot
    var root = storyboard.objectValue ?? [:]
    var scenes = root["scenes"]?.arrayValue ?? []
    for i in scenes.indices {
      var o = scenes[i].objectValue ?? [:]
      let before = o["target_seconds"]?.doubleValue
        ?? o["clip_seconds"]?.doubleValue
        ?? phrase
      let snapped = max(phrase, (before / phrase).rounded() * phrase)
      let fixed = (snapped * 1000).rounded() / 1000
      o["target_seconds"] = .number(fixed)
      scenes[i] = .object(o)
    }
    root["scenes"] = .array(scenes)
    return .object(root)
  }

  /// Build characterRefs map for bundle from bound cast members (web synthesizeUploadsFromCast).
  public static func characterRefs(
    useCharacters: [String],
    castBindings: [String: String],
    cast: [CastMember],
    inlineNames: [String: (name: String, bible: String)] = [:]
  ) -> JSONValue {
    var out: [String: JSONValue] = [:]
    let byId = Dictionary(uniqueKeysWithValues: cast.map { ($0.id, $0) })
    for slot in useCharacters {
      if let castId = castBindings[slot], let m = byId[castId] {
        var training: [JSONValue] = []
        if let pk = m.portrait_key, !pk.isEmpty {
          training.append(.object(["key": .string(pk)]))
        }
        for key in m.refKeys {
          training.append(.object(["key": .string(key)]))
        }
        // Also accept source keys as training fallbacks when no refs yet.
        if training.isEmpty {
          for key in m.sourceKeys {
            training.append(.object(["key": .string(key)]))
          }
        }
        out[slot] = .object([
          "name": .string(m.name),
          "prompt": .string(m.bible ?? ""),
          "trainingImages": .array(training),
        ])
      } else if let inline = inlineNames[slot] {
        out[slot] = .object([
          "name": .string(inline.name),
          "prompt": .string(inline.bible),
          "trainingImages": .array([]),
        ])
      }
    }
    return .object(out)
  }
}

public extension CastMember {
  /// Flatten CONTRACT `ref_keys` (preferred) or legacy `refs` blob into R2 keys.
  var refKeys: [String] {
    if let ref_keys, !ref_keys.isEmpty {
      return ref_keys.map(\.key)
    }
    return Self.keys(from: refs)
  }

  var sourceKeys: [String] {
    if let source_keys, !source_keys.isEmpty {
      return source_keys.map(\.key)
    }
    return Self.keys(from: sources)
  }

  private static func keys(from value: JSONValue?) -> [String] {
    guard let value else { return [] }
    switch value {
    case .array(let arr):
      return arr.compactMap { item in
        if let s = item.stringValue { return s }
        return item.objectValue?["key"]?.stringValue
      }
    case .object(let o):
      if let arr = o["keys"]?.arrayValue {
        return arr.compactMap(\.stringValue)
      }
      return o.keys.sorted()
    case .string(let s):
      return [s]
    default:
      return []
    }
  }
}
