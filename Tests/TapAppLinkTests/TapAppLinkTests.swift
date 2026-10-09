import XCTest
import TapAppLink

final class TapAppLinkTests: XCTestCase {
  override func setUp() {
    super.setUp()
    TapAppLink.resetForTesting()
  }

  override func tearDown() {
    TapAppLink.resetForTesting()
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
}
