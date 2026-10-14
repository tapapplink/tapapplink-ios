import XCTest
@testable import TapAppLink

final class TapAppLinkIdentifyTests: XCTestCase {
  override func setUp() {
    super.setUp()
    TapAppLink.resetForTesting()
    MockURLProtocol.reset()
  }

  override func tearDown() {
    TapAppLink.resetForTesting()
    MockURLProtocol.reset()
    super.tearDown()
  }

  func testSetAppUserIdSkipsWhenSameAsLastSuccessfulIdentify() async throws {
    installMockSession()
    configureForMock()

    MockURLProtocol.stub = .init(
      statusCode: 200,
      jsonObject: ["attributionId": "attr_id", "matched": false]
    )
    _ = try await TapAppLink.trackInstall()

    MockURLProtocol.stub = .init(
      statusCode: 200,
      jsonObject: ["ok": true]
    )
    let first = try await TapAppLink.setAppUserId("user_same")
    let second = try await TapAppLink.setAppUserId("user_same")

    XCTAssertEqual(first["ok"] as? Bool, true)
    XCTAssertEqual(second["skipped"] as? Bool, true)
    XCTAssertEqual(second["appUserId"] as? String, "user_same")
    XCTAssertEqual(second["attributionId"] as? String, "attr_id")
    XCTAssertEqual(MockURLProtocol.requestCount, 2)
    XCTAssertEqual(TapAppLink.getAppUserId(), "user_same")
  }

  func testSetAppUserIdSkipsAfterColdStartWithPersistedId() async throws {
    installMockSession()
    configureForMock()

    MockURLProtocol.stub = .init(
      statusCode: 200,
      jsonObject: ["attributionId": "attr_cold_id", "matched": false]
    )
    _ = try await TapAppLink.trackInstall()

    MockURLProtocol.stub = .init(
      statusCode: 200,
      jsonObject: ["ok": true]
    )
    _ = try await TapAppLink.setAppUserId("user_persisted")
    XCTAssertEqual(MockURLProtocol.requestCount, 2)

    TapAppLink.simulateColdLaunchForTesting()
    MockURLProtocol.reset()
    installMockSession()
    configureForMock()

    let resumed = try await TapAppLink.setAppUserId("user_persisted")

    XCTAssertEqual(resumed["skipped"] as? Bool, true)
    XCTAssertEqual(resumed["appUserId"] as? String, "user_persisted")
    XCTAssertEqual(resumed["attributionId"] as? String, "attr_cold_id")
    XCTAssertEqual(MockURLProtocol.requestCount, 0)
    XCTAssertEqual(TapAppLink.getAppUserId(), "user_persisted")
  }

  func testSetAppUserIdCoalescesConcurrentIdenticalCalls() async throws {
    installMockSession()
    configureForMock()

    MockURLProtocol.stub = .init(
      statusCode: 200,
      jsonObject: ["attributionId": "attr_race", "matched": false]
    )
    _ = try await TapAppLink.trackInstall()

    let gate = DispatchSemaphore(value: 0)
    let entered = DispatchSemaphore(value: 0)
    MockURLProtocol.stub = .init(
      statusCode: 200,
      jsonObject: ["ok": true],
      beforeRespond: {
        entered.signal()
        gate.wait()
      }
    )

    async let a = TapAppLink.setAppUserId("user_race")
    // Wait off the cooperative pool until the first POST is in-flight.
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      DispatchQueue.global().async {
        entered.wait()
        continuation.resume()
      }
    }
    async let b = TapAppLink.setAppUserId("user_race")
    async let c = TapAppLink.setAppUserId("user_race")
    gate.signal()

    let results = try await [a, b, c]
    XCTAssertEqual(results[0]["ok"] as? Bool, true)
    XCTAssertEqual(results[1]["ok"] as? Bool, true)
    XCTAssertEqual(results[2]["ok"] as? Bool, true)

    let identifyCalls = MockURLProtocol.capturedRequests.filter {
      $0.url?.absoluteString.contains("/ingestIdentify") == true
    }
    XCTAssertEqual(identifyCalls.count, 1)
  }

  func testSetAppUserIdPostsAgainWhenIdChanges() async throws {
    installMockSession()
    configureForMock()

    MockURLProtocol.stub = .init(
      statusCode: 200,
      jsonObject: ["attributionId": "attr_change", "matched": false]
    )
    _ = try await TapAppLink.trackInstall()

    var identifyBodies: [[String: Any]] = []
    MockURLProtocol.stub = .init(
      statusCode: 200,
      jsonObject: ["ok": true],
      captureRequest: { request in
        if let body = TestHTTPHelpers.requestJSON(request) {
          identifyBodies.append(body)
        }
      }
    )
    _ = try await TapAppLink.setAppUserId("user_a")
    _ = try await TapAppLink.setAppUserId("user_b")

    XCTAssertEqual(identifyBodies.count, 2)
    XCTAssertEqual(identifyBodies[0]["appUserId"] as? String, "user_a")
    XCTAssertEqual(identifyBodies[1]["appUserId"] as? String, "user_b")
    XCTAssertEqual(TapAppLink.getAppUserId(), "user_b")
  }

  func testSetAppUserIdDoesNotSkipAfterFailedIdentify() async throws {
    installMockSession()
    configureForMock()

    MockURLProtocol.stub = .init(
      statusCode: 200,
      jsonObject: ["attributionId": "attr_fail", "matched": false]
    )
    _ = try await TapAppLink.trackInstall()

    MockURLProtocol.stub = .init(
      statusCode: 500,
      jsonObject: ["message": "identify failed"]
    )
    do {
      _ = try await TapAppLink.setAppUserId("user_retry")
      XCTFail("Expected TapAppLinkError.requestFailed")
    } catch TapAppLinkError.requestFailed {
      // Expected: failed identify must not be persisted as successful.
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    MockURLProtocol.stub = .init(
      statusCode: 200,
      jsonObject: ["ok": true]
    )
    let retry = try await TapAppLink.setAppUserId("user_retry")
    XCTAssertEqual(retry["ok"] as? Bool, true)

    let identifyCalls = MockURLProtocol.capturedRequests.filter {
      $0.url?.absoluteString.contains("/ingestIdentify") == true
    }
    XCTAssertEqual(identifyCalls.count, 2)
    XCTAssertEqual(TapAppLink.getAppUserId(), "user_retry")
  }

  private func configureForMock() {
    TapAppLink.configure(
      .init(
        publicKey: "etk_test_key",
        environment: .sandbox,
        ingestUrl: "https://example.invalid"
      )
    )
  }

  private func installMockSession() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    TapAppLink.setURLSessionForTesting(URLSession(configuration: configuration))
  }
}
