import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Extends wall-clock for in-flight render polls when the app backgrounds.
/// Not a full BGAppRefresh task (those need special entitlements and still get
/// short windows); this uses `beginBackgroundTask` so an active poll loop can
/// finish a few more ticks after the user leaves the app.
enum BackgroundPoll {
  #if canImport(UIKit)
  private static var taskId: UIBackgroundTaskIdentifier = .invalid
  #endif

  static func begin(_ name: String = "vivijure-render-poll") {
    #if canImport(UIKit)
    end()
    taskId = UIApplication.shared.beginBackgroundTask(withName: name) {
      end()
    }
    #endif
  }

  static func end() {
    #if canImport(UIKit)
    if taskId != .invalid {
      UIApplication.shared.endBackgroundTask(taskId)
      taskId = .invalid
    }
    #endif
  }
}
