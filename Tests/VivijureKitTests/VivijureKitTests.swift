import XCTest
@testable import VivijureKit

final class VivijureKitTests: XCTestCase {
  func testClientHoldsBaseURL() {
    let url = URL(string: "https://studio.example.com")!
    let client = VivijureClient(baseURL: url)
    XCTAssertEqual(client.baseURL, url)
  }
}
