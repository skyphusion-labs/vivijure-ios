import SwiftUI
import VivijureKit

struct ModulesView: View {
  @EnvironmentObject private var app: AppState

  var body: some View {
    NavigationStack {
      List {
        if let mods = app.modules {
          Section("Host") {
            if mods.readonly == true {
              Text("Read-only mode").foregroundStyle(.orange)
            }
            Text("Quality tiers: \(mods.qualityTiers.joined(separator: ", "))")
              .font(.caption)
          }
          Section("Projection (raw)") {
            Text(prettyModules(mods))
              .font(.system(.caption2, design: .monospaced))
              .textSelection(.enabled)
          }
        } else {
          Text("Load studio connection to see modules.")
            .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("Modules")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            Task { await app.bootstrap() }
          } label: {
            Image(systemName: "arrow.clockwise")
          }
        }
      }
    }
  }

  private func prettyModules(_ m: ModulesResponse) -> String {
    var root: [String: JSONValue] = [:]
    if let modules = m.modules { root["modules"] = .array(modules) }
    if let hooks = m.hooks { root["hooks"] = hooks }
    if let catalog = m.catalog { root["catalog"] = catalog }
    if let render = m.render { root["render"] = render }
    if let api = m.api { root["api"] = api }
    if let ro = m.readonly { root["readonly"] = .bool(ro) }
    return JSONValue.object(root).prettyJSON()
  }
}
