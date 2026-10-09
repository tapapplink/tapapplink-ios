import XCTest
@testable import TapAppLink

final class TapAppLinkRedeemRequestIdTests: XCTestCase {
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

  func testNormalizeCodeUppercasesStripsAndTruncates() {
    XCTAssertEqual(TapAppLink.normalizeCodeForTesting("sarah-10"), "SARAH10")
    XCTAssertEqual(TapAppLink.normalizeCodeForTesting("  ab cd! "), "ABCD")
    let long = String(repeating: "a", count: 40)
    XCTAssertEqual(TapAppLink.normalizeCodeForTesting(long).count, 24)
    XCTAssertEqual(
      TapAppLink.normalizeCodeForTesting(long),
      String(repeating: "A", count: 24)
    )
  }

  func testApplyCodeRetryAfterTimeoutReusesRequestId() async {
    installMockSession()
    configureForMock()

    var firstBody: [String: Any]?
    MockURLProtocol.stub = .init(
      statusCode: 0,
      jsonObject: [:],
      error: URLError(.timedOut),
      captureRequest: { firstBody = TestHTTPHelpers.requestJSON($0) }
    )

    do {
      _ = try await TapAppLink.applyCode("SARAH10")
      XCTFail("Expected network timeout")
    } catch TapAppLinkRedeemError.network {
      // Expected
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    let pendingId = TapAppLink.pendingRedeemRequestIdForTesting()
    XCTAssertEqual(firstBody?["requestId"] as? String, pendingId)
    XCTAssertNotNil(pendingId)

    var secondBody: [String: Any]?
    MockURLProtocol.stub = .init(
      statusCode: 200,
      jsonObject: [
        "attributionId": "attr-retry",
        "alreadyAttributed": false,
      ],
      captureRequest: { secondBody = TestHTTPHelpers.requestJSON($0) }
    )

    do {
      _ = try await TapAppLink.applyCode("sarah-10")
    } catch {
      XCTFail("Expected success on retry: \(error)")
      return
    }
    XCTAssertEqual(secondBody?["requestId"] as? String, pendingId)
    XCTAssertNil(TapAppLink.pendingRedeemRequestIdForTesting())
  }

  func testApplyCodeRestartWithPendingAttemptReusesRequestId() async {
    installMockSession()
    configureForMock()

    var firstBody: [String: Any]?
    MockURLProtocol.stub = .init(
      statusCode: 0,
      jsonObject: [:],
      error: URLError(.timedOut),
      captureRequest: { firstBody = TestHTTPHelpers.requestJSON($0) }
    )

    do {
      _ = try await TapAppLink.applyCode("SARAH10")
      XCTFail("Expected network timeout")
    } catch TapAppLinkRedeemError.network {
      // Expected
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    let pendingId = firstBody?["requestId"] as? String
    XCTAssertNotNil(pendingId)
    XCTAssertEqual(TapAppLink.pendingRedeemRequestIdForTesting(), pendingId)

    // Cold launch drops memory; UserDefaults still holds the pending attempt.
    TapAppLink.simulateColdLaunchForTesting()
    installMockSession()
    configureForMock()
    XCTAssertEqual(TapAppLink.pendingRedeemRequestIdForTesting(), pendingId)

    var secondBody: [String: Any]?
    MockURLProtocol.stub = .init(
      statusCode: 200,
      jsonObject: ["attributionId": "attr-restart"],
      captureRequest: { secondBody = TestHTTPHelpers.requestJSON($0) }
    )

    do {
      _ = try await TapAppLink.applyCode("SARAH10")
    } catch {
      XCTFail("Expected success after restart: \(error)")
      return
    }
    XCTAssertEqual(secondBody?["requestId"] as? String, pendingId)
    XCTAssertNil(TapAppLink.pendingRedeemRequestIdForTesting())
  }

  func testApplyCodeNewCodeClearsPreviousPendingRequestId() async {
    installMockSession()
    configureForMock()

    var firstBody: [String: Any]?
    MockURLProtocol.stub = .init(
      statusCode: 0,
      jsonObject: [:],
      error: URLError(.timedOut),
      captureRequest: { firstBody = TestHTTPHelpers.requestJSON($0) }
    )
    do {
      _ = try await TapAppLink.applyCode("SARAH10")
    } catch TapAppLinkRedeemError.network {
      // Expected
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    let firstId = firstBody?["requestId"] as? String
    XCTAssertNotNil(firstId)

    var secondBody: [String: Any]?
    MockURLProtocol.stub = .init(
      statusCode: 0,
      jsonObject: [:],
      error: URLError(.timedOut),
      captureRequest: { secondBody = TestHTTPHelpers.requestJSON($0) }
    )
    do {
      _ = try await TapAppLink.applyCode("ALEX5")
    } catch TapAppLinkRedeemError.network {
      // Expected
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    let secondId = secondBody?["requestId"] as? String
    XCTAssertNotNil(secondId)
    XCTAssertNotEqual(firstId, secondId)
    XCTAssertEqual(TapAppLink.pendingRedeemRequestIdForTesting(), secondId)
  }

  func testApplyCodeDefinitiveErrorClearsPendingRequestId() async {
    installMockSession()
    configureForMock()

    MockURLProtocol.stub = .init(
      statusCode: 0,
      jsonObject: [:],
      error: URLError(.timedOut)
    )
    do {
      _ = try await TapAppLink.applyCode("SARAH10")
    } catch TapAppLinkRedeemError.network {
      // Expected
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    XCTAssertNotNil(TapAppLink.pendingRedeemRequestIdForTesting())

    MockURLProtocol.stub = .init(
      statusCode: 404,
      jsonObject: ["error": "unknown_code"]
    )
    do {
      _ = try await TapAppLink.applyCode("SARAH10")
      XCTFail("Expected unknownCode")
    } catch TapAppLinkRedeemError.unknownCode {
      XCTAssertNil(TapAppLink.pendingRedeemRequestIdForTesting())
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
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
