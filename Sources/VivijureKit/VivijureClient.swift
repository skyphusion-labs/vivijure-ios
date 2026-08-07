import Foundation

/// HTTP client for a Vivijure Studio host (`vivijure-cf` or `vivijure-local`).
///
/// Skeleton: wire `STUDIO_URL` + Bearer token auth to CONTRACT routes
/// (`/api/modules`, projects, cast, film submit/poll, artifacts). Expand in lockstep
/// with host `docs/CONTRACT.md`.
public struct VivijureClient: Sendable {
  public var baseURL: URL
  public var bearerToken: String?

  public init(baseURL: URL, bearerToken: String? = nil) {
    self.baseURL = baseURL
    self.bearerToken = bearerToken
  }
}
