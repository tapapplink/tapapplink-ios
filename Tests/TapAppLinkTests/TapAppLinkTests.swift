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
    XCTAssertEqual(TapAppLink.sdkVersion, "0.3.1")
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

  // MARK: - applyCode typed errors

  func testApplyCodeSuccessSendsVersionHeaderAndCachesOffer() async throws {
    var captured: URLRequest?
    installMockSession()
    MockURLProtocol.stub = .init(
      statusCode: 200,
      jsonObject: [
        "attributionId": "attr-new",
        "alreadyAttributed": false,
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

    XCTAssertEqual(result["attributionId"] as? String, "attr-new")
    XCTAssertEqual(TapAppLink.getAttributionId(), "attr-new")
    XCTAssertEqual(TapAppLink.getOffer()?.promoCode, "SARAH10")
    XCTAssertEqual(
      captured?.value(forHTTPHeaderField: "X-TapAppLink-SDK-Version"),
      "0.3.1"
    )
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
        "0.3.1"
      )
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }
}
