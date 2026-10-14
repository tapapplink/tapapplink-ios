import XCTest
@testable import TapAppLink

final class TapAppLinkTests: XCTestCase {
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

  func testConfigureStoresPublicKeyAndEnvironment() {
    TapAppLink.configure(
      .init(publicKey: "etk_test_key", environment: .sandbox)
    )

    XCTAssertNil(TapAppLink.getOffer())
    XCTAssertNil(TapAppLink.getAttributionId())
    XCTAssertNil(TapAppLink.getAppUserId())
  }

  func testGettersReturnNilAfterReset() {
    TapAppLink.seedPersistedStateForTesting(
      installId: "install-seed",
      tracked: true,
      attributionId: "attr-seed",
      offer: TapAppLinkOffer(creatorName: "Sarah", promoCode: "SARAH10")
    )
    TapAppLink.configure(
      .init(publicKey: "etk_test_key", environment: .production)
    )
    TapAppLink.resetForTesting()

    XCTAssertNil(TapAppLink.getOffer())
    XCTAssertNil(TapAppLink.getAttributionId())
    XCTAssertNil(TapAppLink.getAppUserId())
    XCTAssertNil(TapAppLink.getInstallId())
  }

  func testEmptyIngestUrlThrowsInvalidURL() async {
    TapAppLink.configure(
      .init(
        publicKey: "etk_test_key",
        environment: .sandbox,
        ingestUrl: ""
      )
    )

    do {
      _ = try await TapAppLink.trackInstall()
      XCTFail("Expected TapAppLinkError.invalidURL")
    } catch TapAppLinkError.invalidURL {
      // Expected: URL(string:) rejects an empty base.
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testConfigInitDefaults() {
    let config = TapAppLinkConfig(
      publicKey: "etk_live_example",
      environment: .production
    )

    XCTAssertEqual(config.publicKey, "etk_live_example")
    XCTAssertEqual(config.environment, .production)
    XCTAssertNil(config.ingestUrl)
    XCTAssertFalse(config.debugLogging)
  }

  func testEnvironmentRawValues() {
    XCTAssertEqual(TapAppLinkEnvironment.production.rawValue, "production")
    XCTAssertEqual(TapAppLinkEnvironment.sandbox.rawValue, "sandbox")
  }

  func testSdkVersionConstant() {
    XCTAssertEqual(TapAppLink.sdkVersion, "0.3.3")
  }

  func testWrongEnvironmentDeveloperWarningCopy() {
    XCTAssertEqual(
      TapAppLinkRedeemError.wrongEnvironmentDeveloperWarning,
      "This code belongs to the other environment (Sandbox or Production). Check your API key."
    )
  }

  func testSecondLaunchWithPersistedStateDoesNotPost() async throws {
    let offer = TapAppLinkOffer(
      creatorName: "Sarah",
      promoCode: "SARAH10",
      billingOfferId: "offer_billing_1"
    )
    TapAppLink.seedPersistedStateForTesting(
      installId: "install-abc",
      tracked: true,
      attributionId: "attr-abc",
      offer: offer
    )

    // Empty ingest URL would throw if trackInstall attempted a network post.
    TapAppLink.configure(
      .init(
        publicKey: "etk_secret_test_key",
        environment: .sandbox,
        ingestUrl: "",
        debugLogging: false
      )
    )

    let result = try await TapAppLink.trackInstall()

    XCTAssertEqual(result["skipped"] as? Bool, true)
    XCTAssertEqual(result["matched"] as? Bool, false)
    XCTAssertEqual(result["installId"] as? String, "install-abc")
    XCTAssertEqual(result["attributionId"] as? String, "attr-abc")

    let returnedOffer = result["offer"] as? [String: Any]
    XCTAssertEqual(returnedOffer?["creatorName"] as? String, "Sarah")
    XCTAssertEqual(returnedOffer?["promoCode"] as? String, "SARAH10")
    XCTAssertEqual(returnedOffer?["billingOfferId"] as? String, "offer_billing_1")

    XCTAssertEqual(TapAppLink.getInstallId(), "install-abc")
    XCTAssertEqual(TapAppLink.getAttributionId(), "attr-abc")
    XCTAssertEqual(TapAppLink.getOffer(), offer)
  }

  func testPersistedStateSurvivesColdLaunch() async throws {
    TapAppLink.seedPersistedStateForTesting(
      installId: "install-persist",
      tracked: true,
      attributionId: "attr-persist",
      offer: TapAppLinkOffer(creatorName: "Alex", promoCode: "ALEX5")
    )
    TapAppLink.simulateColdLaunchForTesting()

    TapAppLink.configure(
      .init(
        publicKey: "etk_test_key",
        environment: .sandbox,
        ingestUrl: ""
      )
    )

    XCTAssertEqual(TapAppLink.getInstallId(), "install-persist")
    XCTAssertEqual(TapAppLink.getAttributionId(), "attr-persist")
    XCTAssertEqual(TapAppLink.getOffer()?.creatorName, "Alex")

    let result = try await TapAppLink.trackInstall()
    XCTAssertEqual(result["skipped"] as? Bool, true)
    XCTAssertEqual(result["attributionId"] as? String, "attr-persist")
  }

  func testIdentifyUsesPersistedAttributionIdWithoutPostingWhenUrlInvalid() async {
    TapAppLink.seedPersistedStateForTesting(
      installId: "install-id",
      tracked: true,
      attributionId: "attr-from-store"
    )
    TapAppLink.configure(
      .init(
        publicKey: "etk_test_key",
        environment: .sandbox,
        ingestUrl: ""
      )
    )

    XCTAssertEqual(TapAppLink.getAttributionId(), "attr-from-store")

    do {
      _ = try await TapAppLink.setAppUserId("user_123")
      XCTFail("Expected TapAppLinkError.invalidURL before any successful post")
    } catch TapAppLinkError.invalidURL {
      // Confirms identify still resolves the stored attribution path to a request attempt.
      XCTAssertEqual(TapAppLink.getAttributionId(), "attr-from-store")
      XCTAssertEqual(TapAppLink.getAppUserId(), "user_123")
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  // MARK: - setAppUserId identify dedupe

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

  // MARK: - applyCode typed errors

  func testApplyCodeSuccessSendsVersionHeaderAndCachesOffer() async throws {
    var captured: URLRequest?
    installMockSession()
    MockURLProtocol.stub = .init(
      statusCode: 200,
      jsonObject: [
        "attributionId": "attr-new",
        "alreadyAttributed": false,
        "codeMatches": true,
        "offer": [
          "creatorName": "Sarah",
          "promoCode": "SARAH10",
          "billingOfferId": "offer_1",
        ],
      ],
      captureRequest: { captured = $0 }
    )

    configureForMock()
    let result = try await TapAppLink.applyCode("SARAH10")

    XCTAssertEqual(result.attributionId, "attr-new")
    XCTAssertEqual(result.alreadyAttributed, false)
    XCTAssertEqual(result.codeMatches, true)
    XCTAssertEqual(result.offer?.creatorName, "Sarah")
    XCTAssertEqual(TapAppLink.getAttributionId(), "attr-new")
    XCTAssertEqual(TapAppLink.getOffer()?.promoCode, "SARAH10")
    XCTAssertEqual(TapAppLink.getOffer()?.creatorName, "Sarah")
    XCTAssertEqual(
      captured?.value(forHTTPHeaderField: "X-TapAppLink-SDK-Version"),
      "0.3.3"
    )
    let body = TestHTTPHelpers.requestJSON(captured)
    XCTAssertNotNil(body?["requestId"] as? String)
    XCTAssertNil(TapAppLink.pendingRedeemRequestIdForTesting())
  }

  func testApplyCodeAlreadyAttributedReturnsSuccessWithOptionalFields() async throws {
    installMockSession()
    MockURLProtocol.stub = .init(
      statusCode: 200,
      jsonObject: [
        "attributionId": "attr-existing",
        "alreadyAttributed": true,
        "codeMatches": false,
        "offer": [
          "creatorName": "Bea",
          "promoCode": "BEA10",
        ],
      ]
    )
    configureForMock()

    let result = try await TapAppLink.applyCode("BEA10")

    XCTAssertEqual(result.attributionId, "attr-existing")
    XCTAssertEqual(result.alreadyAttributed, true)
    XCTAssertEqual(result.codeMatches, false)
    XCTAssertEqual(result.offer?.creatorName, "Bea")
    XCTAssertEqual(TapAppLink.getOffer()?.creatorName, "Bea")
  }

  func testApplyCodeLegacy404UnknownCodeBody() async {
    await assertApplyCodeError(
      status: 404,
      body: ["error": "unknown_code", "message": "No such code"],
      expected: .unknownCode
    )
  }

  func testApplyCodeLegacy404StatusFallback() async {
    await assertApplyCodeError(
      status: 404,
      body: ["message": "missing"],
      expected: .unknownCode
    )
  }

  func testApplyCode410InactiveCodeBody() async {
    await assertApplyCodeError(
      status: 410,
      body: ["error": "inactive_code", "message": "Expired"],
      expected: .inactiveCode
    )
  }

  func testApplyCode410StatusFallback() async {
    await assertApplyCodeError(
      status: 410,
      body: [:],
      expected: .inactiveCode
    )
  }

  func testApplyCode400WrongEnvironmentBody() async {
    await assertApplyCodeError(
      status: 400,
      body: ["error": "wrong_environment", "message": "Sandbox vs Production"],
      expected: .wrongEnvironment
    )
  }

  func testApplyCode400WithoutWrongEnvironmentIsOther() async {
    await assertApplyCodeError(
      status: 400,
      body: ["error": "bad_request", "message": "Malformed"],
      expected: .other(status: 400, message: "Malformed")
    )
  }

  func testApplyCodeInactiveCodePrefersBodyOverStatus() async {
    await assertApplyCodeError(
      status: 404,
      body: ["error": "inactive_code"],
      expected: .inactiveCode
    )
  }

  func testApplyCodeNetworkTimeout() async {
    installMockSession()
    MockURLProtocol.stub = .init(
      statusCode: 0,
      jsonObject: [:],
      error: URLError(.timedOut)
    )
    configureForMock()

    do {
      _ = try await TapAppLink.applyCode("SARAH10")
      XCTFail("Expected TapAppLinkRedeemError.network")
    } catch TapAppLinkRedeemError.network {
      // Expected
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testTrackInstallNon2xxThrowsRequestFailedNotSuccessBody() async {
    installMockSession()
    MockURLProtocol.stub = .init(
      statusCode: 500,
      jsonObject: ["error": "server_error", "matched": true]
    )
    configureForMock()

    do {
      _ = try await TapAppLink.trackInstall()
      XCTFail("Expected TapAppLinkError.requestFailed")
    } catch TapAppLinkError.requestFailed {
      XCTAssertNil(TapAppLink.getAttributionId())
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testRedeemErrorMappingHelpers() {
    XCTAssertEqual(
      TapAppLinkRedeemError.from(status: 404, body: ["error": "unknown_code"]),
      .unknownCode
    )
    XCTAssertEqual(
      TapAppLinkRedeemError.from(status: 410, body: ["error": "inactive_code"]),
      .inactiveCode
    )
    XCTAssertEqual(
      TapAppLinkRedeemError.from(status: 400, body: ["error": "wrong_environment"]),
      .wrongEnvironment
    )
    XCTAssertEqual(
      TapAppLinkRedeemError.from(status: 404, body: [:]),
      .unknownCode
    )
    XCTAssertEqual(
      TapAppLinkRedeemError.from(status: 410, body: [:]),
      .inactiveCode
    )
    XCTAssertEqual(
      TapAppLinkRedeemError.from(status: 500, body: ["message": "boom"]),
      .other(status: 500, message: "boom")
    )
  }

  // MARK: - Helpers

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

  private func assertApplyCodeError(
    status: Int,
    body: [String: Any],
    expected: TapAppLinkRedeemError
  ) async {
    var captured: URLRequest?
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    TapAppLink.setURLSessionForTesting(URLSession(configuration: configuration))
    MockURLProtocol.stub = .init(
      statusCode: status,
      jsonObject: body,
      captureRequest: { captured = $0 }
    )
    configureForMock()

    do {
      _ = try await TapAppLink.applyCode("SARAH10")
      XCTFail("Expected \(expected)")
    } catch let error as TapAppLinkRedeemError {
      XCTAssertEqual(error, expected)
      XCTAssertEqual(
        captured?.value(forHTTPHeaderField: "X-TapAppLink-SDK-Version"),
        "0.3.3"
      )
      XCTAssertNotNil(TestHTTPHelpers.requestJSON(captured)?["requestId"] as? String)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }
}
