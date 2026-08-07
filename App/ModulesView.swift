import SwiftUI
import VivijureKit

struct ModulesView: View {
  @EnvironmentObject private var app: AppState
  @State private var scriptName = ""
  @State private var configModule = ""
  @State private var configJSON = ""
  @State private var configStatus = ""

  var body: some View {
    NavigationStack {
      List {
        if let mods = app.modules {
          Section("Host projection") {
            if mods.readonly == true {
              Text("Read-only mode").foregroundStyle(.orange)
            }
            Text("Quality tiers: \(mods.qualityTiers.joined(separator: ", "))")
              .font(.caption)
            if let hooks = mods.hooks {
              Text("Hooks: \(hookSummary(hooks))")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
          }
          Section("Installed manifests (from GET /api/modules)") {
            ForEach(moduleEntries(mods), id: \.name) { entry in
              VStack(alignment: .leading, spacing: 4) {
                Text(entry.name).font(.headline)
                if let hooks = entry.hooks, !hooks.isEmpty {
                  Text(hooks.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Button("Edit install-scope config") {
                  configModule = entry.name
                  Task { await loadConfig(entry.name) }
                }
                .font(.caption)
              }
            }
          }
          if !configModule.isEmpty {
            Section("Config: \(configModule)") {
              TextEditor(text: $configJSON)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 120)
              Button("Save PATCH /api/modules/\(configModule)/config") {
                Task { await saveConfig() }
              }
              .disabled(app.busy)
              if !configStatus.isEmpty {
                Text(configStatus).font(.caption2)
              }
            }
          }
          Section("Dispatch install (MODULE_DISPATCH hosts)") {
            TextField("script_name", text: $scriptName)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
            Button("Install") {
              let n = scriptName.trimmingCharacters(in: .whitespacesAndNewlines)
              guard !n.isEmpty else { return }
              Task { await app.installModule(scriptName: n) }
            }
            .disabled(app.busy)
            Button("Refresh installed registry") {
              Task { await app.refreshInstalledModules() }
            }
            ForEach(installedNames, id: \.self) { name in
              HStack {
                Text(name)
                Spacer()
                Button("Off") {
                  Task { await app.setModuleEnabled(name: name, enabled: false) }
                }
                .font(.caption)
                Button("On") {
                  Task { await app.setModuleEnabled(name: name, enabled: true) }
                }
                .font(.caption)
                Button("Uninstall", role: .destructive) {
                  Task { await app.uninstallModule(name: name) }
                }
                .font(.caption)
              }
            }
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
            Task {
              await app.bootstrap()
              await app.refreshInstalledModules()
            }
          } label: {
            Image(systemName: "arrow.clockwise")
          }
        }
      }
      .task {
        await app.refreshInstalledModules()
      }
    }
  }

  private var installedNames: [String] {
    app.installedModules.compactMap { $0.objectValue?["name"]?.stringValue
      ?? $0.objectValue?["module"]?.stringValue
      ?? $0.stringValue }
  }

  private struct ModEntry {
    var name: String
    var hooks: [String]?
  }

  private func moduleEntries(_ m: ModulesResponse) -> [ModEntry] {
    (m.modules ?? []).compactMap { mod in
      guard let o = mod.objectValue, let name = o["name"]?.stringValue else { return nil }
      var hooks: [String] = []
      if let provides = o["provides"]?.arrayValue {
        hooks = provides.compactMap { $0.objectValue?["id"]?.stringValue ?? $0.stringValue }
      }
      if hooks.isEmpty, let h = o["hooks"]?.arrayValue {
        hooks = h.compactMap(\.stringValue)
      }
      return ModEntry(name: name, hooks: hooks.isEmpty ? nil : hooks)
    }
  }

  private func hookSummary(_ hooks: JSONValue) -> String {
    guard case .object(let o) = hooks else { return hooks.prettyJSON() }
    return o.keys.sorted().joined(separator: ", ")
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

  private func loadConfig(_ name: String) async {
    if let cfg = await app.loadModuleConfig(name: name) {
      configJSON = cfg.prettyJSON()
      configStatus = "Loaded"
    } else {
      configJSON = "{}"
      configStatus = "No install-scope config (or 404)"
    }
  }

  private func saveConfig() async {
    guard let data = configJSON.data(using: .utf8),
          let any = try? JSONSerialization.jsonObject(with: data),
          JSONSerialization.isValidJSONObject(any)
    else {
      configStatus = "Invalid JSON"
      return
    }
    let value = JSONValue.from(any)
    await app.saveModuleConfig(name: configModule, config: value)
    configStatus = "Saved"
  }
}
