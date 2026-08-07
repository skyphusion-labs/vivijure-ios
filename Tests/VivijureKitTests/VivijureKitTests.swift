import XCTest
@testable import VivijureKit

final class VivijureKitTests: XCTestCase {
  func testClientHoldsBaseURL() throws {
    let url = URL(string: "https://studio.example.com")!
    let client = VivijureClient(baseURL: url, bearerToken: "tok")
    XCTAssertEqual(client.baseURL, url)
    XCTAssertEqual(client.bearerToken, "tok")
  }

  func testJSONValueRoundTrip() throws {
    let original: JSONValue = .object([
      "title": .string("Film"),
      "scenes": .array([
        .object(["id": .string("s1"), "prompt": .string("wide shot")]),
      ]),
      "duration_seconds": .number(12),
    ])
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    XCTAssertEqual(decoded, original)
    XCTAssertTrue(decoded.prettyJSON().contains("wide shot"))
  }

  func testPlanRequestEncodes() throws {
    let body = PlanRequest(brief: "noir short", model: "m1")
    let data = try JSONEncoder().encode(body)
    let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    XCTAssertEqual(obj?["brief"] as? String, "noir short")
    XCTAssertEqual(obj?["model"] as? String, "m1")
  }

  func testURLJoin() throws {
    let http = HTTPClient(baseURL: URL(string: "https://studio.example.com/base")!)
    let u = try http.url(path: "/api/modules")
    XCTAssertEqual(u.absoluteString, "https://studio.example.com/base/api/modules")
  }

  func testModulesQualityTiersFallback() {
    let empty = try! JSONDecoder().decode(ModulesResponse.self, from: Data("{}".utf8))
    XCTAssertFalse(empty.qualityTiers.isEmpty)
  }

  func testSceneEditRoundTrip() {
    let sb: JSONValue = .object([
      "use_characters": .array([.string("A")]),
      "scenes": .array([
        .object([
          "id": .string("s1"),
          "prompt": .string("wide"),
          "target_seconds": .number(3),
          "character_slots": .array([.string("A")]),
          "dialogue": .object(["slot": .string("A"), "text": .string("hi")]),
        ]),
      ]),
    ])
    var edits = SceneEdit.from(storyboard: sb)
    XCTAssertEqual(edits.count, 1)
    XCTAssertEqual(edits[0].prompt, "wide")
    edits[0].prompt = "close-up"
    edits[0].targetSeconds = 4
    let next = StoryboardMutator.applyScenes(edits, to: sb)
    let scenes = next.objectValue?["scenes"]?.arrayValue
    XCTAssertEqual(scenes?.first?.objectValue?["prompt"]?.stringValue, "close-up")
    XCTAssertEqual(scenes?.first?.objectValue?["target_seconds"]?.doubleValue, 4)
  }

  func testSnapToBeats() {
    let sb: JSONValue = .object([
      "scenes": .array([
        .object(["id": .string("s1"), "target_seconds": .number(1.0)]),
      ]),
    ])
    // 120 BPM, 4 beats = 2.0s phrase; 1.0 snaps to 2.0
    let next = StoryboardMutator.snapScenesToBeats(storyboard: sb, bpm: 120, beatsPerShot: 4)
    XCTAssertEqual(
      next.objectValue?["scenes"]?.arrayValue?.first?.objectValue?["target_seconds"]?.doubleValue,
      2.0
    )
  }

  func testCharacterRefsFromCast() {
    let cast = [
      CastMember(
        id: "c1",
        name: "Elena",
        bible: "red coat",
        voice_id: nil,
        portrait_key: "cast/1/portrait.png",
        portrait_mime: "image/png",
        lora_status: nil,
        ref_keys: [CastImageKey(key: "cast/1/refs/a.png")],
        source_keys: nil,
        refs: nil,
        sources: nil
      ),
    ]
    // CastMember needs a memberwise init - may not have one if only Codable synthesized.
    // Use JSON decode instead if memberwise missing.
    let refs = StoryboardMutator.characterRefs(
      useCharacters: ["A"],
      castBindings: ["A": "c1"],
      cast: cast
    )
    let slot = refs.objectValue?["A"]?.objectValue
    XCTAssertEqual(slot?["name"]?.stringValue, "Elena")
    XCTAssertEqual(slot?["trainingImages"]?.arrayValue?.count, 2)
  }

  func testCastMemberRefKeysDecode() throws {
    let json = """
    {"id":"x","name":"N","portrait_key":"p","ref_keys":[{"key":"r1","mime":"image/png"}],"source_keys":[]}
    """
    let m = try JSONDecoder().decode(CastMember.self, from: Data(json.utf8))
    XCTAssertEqual(m.refKeys, ["r1"])
    XCTAssertEqual(m.portrait_key, "p")
  }
}
