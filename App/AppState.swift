import Foundation
import SwiftUI
import VivijureKit

@MainActor
final class AppState: ObservableObject {
  @Published var studioURLString: String = ""
  @Published var token: String = ""
  @Published var isConfigured: Bool = false
  @Published var whoami: WhoamiResponse?
  @Published var modules: ModulesResponse?
  @Published var statusMessage: String = ""
  @Published var lastError: String?

  // Planner session (mirrors web localStorage session)
  @Published var projects: [StoryboardProject] = []
  @Published var selectedProjectId: Int?
  @Published var brief: String = ""
  @Published var planModel: String = ""
  @Published var storyboard: JSONValue?
  @Published var preflight: PreflightResponse?
  @Published var bundleKey: String?
  @Published var renderJobId: String?
  @Published var renderStatus: String = ""
  @Published var cast: [CastMember] = []
  @Published var renders: [RenderRow] = []
  @Published var plannerStep: PlannerStep = .plan
  @Published var qualityTier: String = "final"
  @Published var audioKey: String?
  @Published var busy: Bool = false

  private let urlKey = "studio_url"
  private let tokenKey = "studio_token"

  enum PlannerStep: String, CaseIterable, Identifiable {
    case plan = "Plan"
    case castBundle = "Cast & Bundle"
    case audio = "Audio"
    case render = "Render"
    case history = "History"
    var id: String { rawValue }
  }

  init() {
    studioURLString = KeychainStore.get(account: urlKey)
      ?? UserDefaults.standard.string(forKey: urlKey)
      ?? ""
    token = KeychainStore.get(account: tokenKey) ?? ""
    isConfigured = !studioURLString.isEmpty && !token.isEmpty
  }

  var client: VivijureClient? {
    guard isConfigured,
          let url = URL(string: studioURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
          url.scheme != nil
    else { return nil }
    return VivijureClient(baseURL: url, bearerToken: token)
  }

  func saveCredentials(url: String, token: String) {
    let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
    let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
    studioURLString = u
    self.token = t
    KeychainStore.set(u, account: urlKey)
    KeychainStore.set(t, account: tokenKey)
    UserDefaults.standard.set(u, forKey: urlKey)
    isConfigured = !u.isEmpty && !t.isEmpty
  }

  func signOut() {
    KeychainStore.delete(account: tokenKey)
    token = ""
    isConfigured = false
    whoami = nil
    modules = nil
    clearPlannerSession()
  }

  func clearPlannerSession() {
    brief = ""
    storyboard = nil
    preflight = nil
    bundleKey = nil
    renderJobId = nil
    renderStatus = ""
    audioKey = nil
    plannerStep = .plan
    selectedProjectId = nil
  }

  func bootstrap() async {
    guard let client else {
      lastError = "Not configured"
      return
    }
    busy = true
    lastError = nil
    defer { busy = false }
    do {
      async let w = client.whoami()
      async let m = client.modules()
      async let p = client.listProjects()
      async let c = client.listCast()
      whoami = try await w
      modules = try await m
      projects = try await p
      cast = try await c
      if planModel.isEmpty {
        planModel = try await pickDefaultModel(client: client)
      }
      qualityTier = modules?.defaultQualityTier ?? "final"
      statusMessage = "Connected as \(whoami?.user ?? whoami?.email ?? "studio")"
    } catch {
      lastError = error.localizedDescription
    }
  }

  private func pickDefaultModel(client: VivijureClient) async throws -> String {
    if let models = try? await client.storyboardModels() {
      if let d = models.default_model, !d.isEmpty { return d }
      if let first = models.models?.first {
        if case .string(let s) = first { return s }
        if case .object(let o) = first, let id = o["id"]?.stringValue ?? o["name"]?.stringValue {
          return id
        }
      }
    }
    return "claude-sonnet-4-5"
  }

  func refreshProjects() async {
    guard let client else { return }
    do { projects = try await client.listProjects() } catch { lastError = error.localizedDescription }
  }

  func refreshCast() async {
    guard let client else { return }
    do { cast = try await client.listCast() } catch { lastError = error.localizedDescription }
  }

  func refreshHistory() async {
    guard let client else { return }
    do { renders = try await client.listRenders(projectId: selectedProjectId) } catch {
      lastError = error.localizedDescription
    }
  }

  func runPlan() async {
    guard let client else { return }
    busy = true
    lastError = nil
    defer { busy = false }
    do {
      let resp = try await client.plan(brief: brief, model: planModel.isEmpty ? nil : planModel)
      if let err = resp.error {
        lastError = err
        return
      }
      guard let sb = resp.storyboard else {
        lastError = "Plan returned no storyboard"
        return
      }
      storyboard = sb
      if let pid = selectedProjectId {
        _ = try await client.saveStoryboard(projectId: pid, storyboard: sb)
        await refreshProjects()
      }
      plannerStep = .castBundle
      statusMessage = "Plan ready"
    } catch {
      lastError = error.localizedDescription
    }
  }

  func runPreflight() async {
    guard let client, let storyboard else { return }
    busy = true
    lastError = nil
    defer { busy = false }
    do {
      preflight = try await client.preflight(PreflightRequest(storyboard: storyboard, quality: qualityTier))
      statusMessage = preflight?.ok == true ? "Preflight OK" : "Preflight has issues"
    } catch {
      lastError = error.localizedDescription
    }
  }

  func runBundle() async {
    guard let client, let storyboard else { return }
    busy = true
    lastError = nil
    defer { busy = false }
    do {
      // Empty characterRefs object: bundle may still assemble for boards without LoRA slots.
      let resp = try await client.bundle(storyboard: storyboard, characterRefs: .object([:]))
      guard let key = resp.key else {
        lastError = resp.error ?? "Bundle returned no key"
        return
      }
      bundleKey = key
      plannerStep = .render
      statusMessage = "Bundled: \(key)"
    } catch {
      lastError = error.localizedDescription
    }
  }

  func runRender() async {
    guard let client, let storyboard else { return }
    busy = true
    lastError = nil
    defer { busy = false }
    do {
      let body = StoryboardRenderRequest(
        storyboard: storyboard,
        bundleKey: bundleKey,
        qualityTier: qualityTier,
        projectId: selectedProjectId
      )
      let job = try await client.submitStoryboardRender(body)
      guard let jid = job.resolvedJobId else {
        lastError = job.error ?? "No job id"
        return
      }
      renderJobId = jid
      renderStatus = job.status ?? job.phase ?? "submitted"
      plannerStep = .history
      statusMessage = "Render \(jid)"
      await pollRenderLoop()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func pollRenderLoop() async {
    guard let client, let jid = renderJobId else { return }
    for _ in 0 ..< 120 {
      do {
        let job = try await client.pollStoryboardRender(jobId: jid)
        renderStatus = job.status ?? job.phase ?? renderStatus
        let done = ["COMPLETED", "FAILED", "CANCELLED", "done", "failed"].contains {
          ($0.caseInsensitiveCompare(renderStatus) == .orderedSame)
        }
        if done {
          statusMessage = "Render \(renderStatus)"
          await refreshHistory()
          return
        }
      } catch {
        lastError = error.localizedDescription
        return
      }
      try? await Task.sleep(nanoseconds: 8_000_000_000)
    }
  }

  func createProject(name: String) async {
    guard let client else { return }
    do {
      let p = try await client.createProject(name: name)
      selectedProjectId = p.id
      await refreshProjects()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func createCastMember(name: String, bible: String?) async {
    guard let client else { return }
    do {
      _ = try await client.createCast(name: name, bible: bible)
      await refreshCast()
    } catch {
      lastError = error.localizedDescription
    }
  }
}
