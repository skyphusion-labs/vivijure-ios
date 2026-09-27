import Foundation

/// Shown when plan or refine is asked for with no model chosen. The host answers 400 without one,
/// and a default the user did not pick would bill a metered call to a model they never chose.
public let missingPlannerModelMessage = "Choose a model first. Plan and refine need one."

/// The model to send on plan or refine, or nil when none is chosen (blank or whitespace only).
public func chosenPlannerModel(_ raw: String) -> String? {
  let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
  return trimmed.isEmpty ? nil : trimmed
}
