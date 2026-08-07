import Foundation

public enum VivijureError: Error, Sendable, LocalizedError {
  case invalidURL(String)
  case missingToken
  case transport(String)
  case http(status: Int, body: String)
  case decoding(String)

  public var errorDescription: String? {
    switch self {
    case .invalidURL(let s): return "Invalid URL: \(s)"
    case .missingToken: return "Studio API token is required"
    case .transport(let s): return "Network error: \(s)"
    case .http(let status, let body):
      let snippet = body.count > 400 ? String(body.prefix(400)) + "…" : body
      return "HTTP \(status): \(snippet)"
    case .decoding(let s): return "Decode error: \(s)"
    }
  }
}
