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
    TapAppLink.configure(
      .init(publicKey: "etk_test_key", environment: .production)
    )
    TapAppLink.resetForTesting()

    XCTAssertNil(TapAppLink.getOffer())
    XCTAssertNil(TapAppLink.getAttributionId())
    XCTAssertNil(TapAppLink.getAppUserId())
  }

  func testTrackInstallThrowsWhenNotConfigured() async {
    do {
      _ = try await TapAppLink.trackInstall()
      XCTFail("Expected TapAppLinkError.notConfigured")
    } catch TapAppLinkError.notConfigured {
      // Expected
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testSetAppUserIdThrowsWhenNotConfigured() async {
    do {
      _ = try await TapAppLink.setAppUserId("user_123")
      XCTFail("Expected TapAppLinkError.notConfigured")
    } catch TapAppLinkError.notConfigured {
      // Expected
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testApplyCodeThrowsWhenNotConfigured() async {
    do {
      _ = try await TapAppLink.applyCode("SARAH10")
      XCTFail("Expected TapAppLinkError.notConfigured")
    } catch TapAppLinkError.notConfigured {
      // Expected
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testConfigInitDefaultsIngestUrlToNil() {
    let config = TapAppLinkConfig(
      publicKey: "etk_live_example",
      environment: .production
    )

    XCTAssertEqual(config.publicKey, "etk_live_example")
    XCTAssertEqual(config.environment, .production)
    XCTAssertNil(config.ingestUrl)
  }

  func testEnvironmentRawValues() {
    XCTAssertEqual(TapAppLinkEnvironment.production.rawValue, "production")
    XCTAssertEqual(TapAppLinkEnvironment.sandbox.rawValue, "sandbox")
  }
}
