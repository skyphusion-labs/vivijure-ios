import SwiftUI

struct RootView: View {
  @EnvironmentObject private var app: AppState

  var body: some View {
    Group {
      if app.isConfigured {
        MainTabView()
          .task { await app.bootstrap() }
      } else {
        OnboardingView()
      }
    }
  }
}

struct MainTabView: View {
  @EnvironmentObject private var app: AppState

  var body: some View {
    TabView {
      PlannerHomeView()
        .tabItem { Label("Planner", systemImage: "film") }
      CastLibraryView()
        .tabItem { Label("Cast", systemImage: "person.3") }
      ModulesView()
        .tabItem { Label("Modules", systemImage: "shippingbox") }
      SettingsView()
        .tabItem { Label("Settings", systemImage: "gearshape") }
    }
  }
}
