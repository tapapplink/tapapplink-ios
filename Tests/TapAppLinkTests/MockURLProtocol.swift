import Foundation

/// In-memory `URLProtocol` stub for SDK HTTP tests.
/// Not `final`: `URLProtocol` requires `class` overrides for `canInit` / `canonicalRequest`.
class MockURLProtocol: URLProtocol, @unchecked Sendable {
  struct Stub {
    var statusCode: Int
    var jsonObject: [String: Any]
    var error: Error?
    var captureRequest: ((URLRequest) -> Void)?
  }

  private static let lock = NSLock()
  private static var _stub: Stub?

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

  static func reset() {
    stub = nil
  }

  override class func canInit(with request: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    guard let stub = Self.stub else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }

    stub.captureRequest?(request)

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
}
