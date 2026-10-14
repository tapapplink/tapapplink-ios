import Foundation

/// In-memory `URLProtocol` stub for SDK HTTP tests.
/// Not `final`: `URLProtocol` requires `class` overrides for `canInit` / `canonicalRequest`.
class MockURLProtocol: URLProtocol, @unchecked Sendable {
  struct Stub {
    var statusCode: Int
    var jsonObject: [String: Any]
    var error: Error?
    /// Invoked on the protocol thread before responding; may block (e.g. wait on a gate).
    var beforeRespond: (() -> Void)?
    var captureRequest: ((URLRequest) -> Void)?
  }

  private static let lock = NSLock()
  private static var _stub: Stub?
  private static var _requestCount = 0
  private static var _capturedRequests: [URLRequest] = []

  static var stub: Stub? {
    get {
      lock.lock()
      defer { lock.unlock() }
      return _stub
    }
    set {
      lock.lock()
      _stub = newValue
      lock.unlock()
    }
  }

  static var requestCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return _requestCount
  }

  static var capturedRequests: [URLRequest] {
    lock.lock()
    defer { lock.unlock() }
    return _capturedRequests
  }

  static func reset() {
    lock.lock()
    _stub = nil
    _requestCount = 0
    _capturedRequests = []
    lock.unlock()
  }

  override class func canInit(with request: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    Self.record(request)

    guard let stub = Self.stub else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }

    stub.captureRequest?(request)
    stub.beforeRespond?()

    if let error = stub.error {
      client?.urlProtocol(self, didFailWithError: error)
      return
    }

    let data: Data
    do {
      data = try JSONSerialization.data(withJSONObject: stub.jsonObject)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
      return
    }

    let url = request.url ?? URL(string: "https://example.invalid") ?? URL(fileURLWithPath: "/")
    guard let response = HTTPURLResponse(
      url: url,
      statusCode: stub.statusCode,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    ) else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}

  private static func record(_ request: URLRequest) {
    lock.lock()
    _requestCount += 1
    _capturedRequests.append(request)
    lock.unlock()
  }
}
