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
}
