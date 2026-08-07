import SwiftUI

@main
struct VivijureApp: App {
  @StateObject private var appState = AppState()

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(appState)
    }
  }
}
