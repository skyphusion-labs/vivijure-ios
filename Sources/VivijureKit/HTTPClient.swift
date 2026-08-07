import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Thin async JSON HTTP helper for the studio Bearer API.
public final class HTTPClient: @unchecked Sendable {
  public let baseURL: URL
  public let session: URLSession

  public init(baseURL: URL, session: URLSession? = nil) {
    self.baseURL = baseURL
    if let session {
      self.session = session
    } else {
      let config = URLSessionConfiguration.ephemeral
      config.timeoutIntervalForRequest = 300
      config.timeoutIntervalForResource = 900
      self.session = URLSession(configuration: config)
    }
  }

  public func url(path: String, query: [URLQueryItem] = []) throws -> URL {
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
      throw VivijureError.invalidURL(baseURL.absoluteString)
    }
    let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let rel = path.hasPrefix("/") ? String(path.dropFirst()) : path
    if basePath.isEmpty {
      components.path = "/" + rel
    } else {
      components.path = "/" + basePath + "/" + rel
    }
    if !query.isEmpty { components.queryItems = query }
    guard let url = components.url else { throw VivijureError.invalidURL(path) }
    return url
  }

  public func request(
    method: String,
    path: String,
    body: Data? = nil,
    contentType: String? = "application/json; charset=utf-8",
    bearer: String?,
    query: [URLQueryItem] = []
  ) throws -> URLRequest {
    var req = URLRequest(url: try url(path: path, query: query))
    req.httpMethod = method
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    if let body {
      if let contentType {
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
      }
      req.httpBody = body
    }
    if let bearer, !bearer.isEmpty {
      req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
    }
    return req
  }

  public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let pair: (Data, URLResponse)
    do {
      #if canImport(FoundationNetworking)
      pair = try await withCheckedThrowingContinuation { cont in
        session.dataTask(with: request) { data, response, error in
          if let error {
            cont.resume(throwing: error)
            return
          }
          cont.resume(returning: (data ?? Data(), response!))
        }.resume()
      }
      #else
      pair = try await session.data(for: request)
      #endif
    } catch {
      throw VivijureError.transport(error.localizedDescription)
    }
    guard let http = pair.1 as? HTTPURLResponse else {
      throw VivijureError.transport("Non-HTTP response")
    }
    return (pair.0, http)
  }

  public func sendJSON<T: Decodable>(
    _ type: T.Type,
    method: String,
    path: String,
    body: (any Encodable)? = nil,
    bearer: String?,
    query: [URLQueryItem] = [],
    allowEmpty: Bool = false
  ) async throws -> T {
    var data: Data?
    if let body {
      let enc = JSONEncoder()
      enc.outputFormatting = [.sortedKeys]
      data = try enc.encode(AnyEncodable(body))
    }
    let req = try request(method: method, path: path, body: data, bearer: bearer, query: query)
    let (respData, http) = try await send(req)
    if http.statusCode >= 400 {
      let text = String(data: respData, encoding: .utf8) ?? ""
      throw VivijureError.http(status: http.statusCode, body: text)
    }
    if respData.isEmpty, allowEmpty {
      throw VivijureError.decoding("Empty body")
    }
    do {
      return try JSONDecoder().decode(T.self, from: respData)
    } catch {
      throw VivijureError.decoding(error.localizedDescription)
    }
  }

  public func sendRaw(
    method: String,
    path: String,
    body: Data,
    contentType: String,
    bearer: String?
  ) async throws -> Data {
    try await sendBytes(method: method, path: path, body: body, contentType: contentType, bearer: bearer)
  }

  /// Raw bytes request (GET export, POST import, image uploads).
  public func sendBytes(
    method: String,
    path: String,
    body: Data? = nil,
    contentType: String? = nil,
    bearer: String?,
    query: [URLQueryItem] = []
  ) async throws -> Data {
    let req = try request(
      method: method,
      path: path,
      body: body,
      contentType: contentType,
      bearer: bearer,
      query: query
    )
    let (respData, http) = try await send(req)
    if http.statusCode >= 400 {
      let text = String(data: respData, encoding: .utf8) ?? ""
      throw VivijureError.http(status: http.statusCode, body: text)
    }
    return respData
  }
}

/// Type-erased Encodable for JSONEncoder.
struct AnyEncodable: Encodable {
  private let encodeFunc: (Encoder) throws -> Void
  init(_ value: any Encodable) {
    encodeFunc = { encoder in try value.encode(to: encoder) }
  }
  func encode(to encoder: Encoder) throws { try encodeFunc(encoder) }
}
