import XCTest
final class DeliberateFailTests: XCTestCase {
  func testDeliberateFail() { XCTFail("deliberate") }
}
