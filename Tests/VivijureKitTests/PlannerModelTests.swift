import XCTest
@testable import VivijureKit

/// Plan and refine need a model: the host answers 400 without one. A blank model is refused
/// locally rather than sent (vivijure-ios#24).
final class PlannerModelTests: XCTestCase {
  func testBlankModelIsNotChosen() {
    XCTAssertNil(chosenPlannerModel(""))
  }

  func testWhitespaceOnlyModelIsNotChosen() {
    XCTAssertNil(chosenPlannerModel("  \n\t "))
  }

  func testChosenModelIsReturned() {
    XCTAssertEqual(chosenPlannerModel("claude-sonnet-4-5"), "claude-sonnet-4-5")
  }

  func testChosenModelIsTrimmed() {
    XCTAssertEqual(chosenPlannerModel("  @cf/meta/llama-3.1-8b-instruct \n"), "@cf/meta/llama-3.1-8b-instruct")
  }

  func testRefusalNamesTheMissingModel() {
    XCTAssertTrue(missingPlannerModelMessage.lowercased().contains("model"))
  }
}
