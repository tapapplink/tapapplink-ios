import Foundation
#if canImport(UIKit)
import UIKit
#endif

public enum TapAppLinkEnvironment: String, Sendable {
  case production
  case sandbox
}

public struct TapAppLinkConfig: Sendable {
  public var publicKey: String
  public var environment: TapAppLinkEnvironment
  public var ingestUrl: String?
  public var debugSessionId: String?

  public init(
    publicKey: String,
    environment: TapAppLinkEnvironment,
    ingestUrl: String? = nil,
    debugSessionId: String? = nil
  ) {
    self.publicKey = publicKey
    self.environment = environment
    self.ingestUrl = ingestUrl
    self.debugSessionId = debugSessionId
  }
}

public struct TapAppLinkOffer: Sendable {
  public var creatorName: String
  public var promoCode: String?
  public var discountBps: Int
  public var billingOfferId: String?
}

public enum TapAppLink {
  private static var config: TapAppLinkConfig?
  private static var tracked = false
  private static var lastAttributionId: String?
  private static var lastAppUserId: String?
  private static var lastOffer: TapAppLinkOffer?
  private static let session = URLSession.shared

  public static func configure(_ next: TapAppLinkConfig) {
    config = next
  }

  @discardableResult
  public static func trackInstall() async throws -> [String: Any] {
    if tracked {
      return ["matched": false, "skipped": true]
    }
    #if canImport(UIKit)
    let deviceFamily = UIDevice.current.model.contains("iPad") ? "iPad" : "iPhone"
    #else
    let deviceFamily = "iPhone"
    #endif
    var body: [String: Any] = [
      "platform": "IOS",
      "deviceFamily": deviceFamily,
      "locale": Locale.current.identifier,
      "networkContext": regionCode(),
      "firstOpenAt": ISO8601DateFormatter().string(from: Date()),
    ]
    if let debugSessionId = config?.debugSessionId {
      body["debugSessionId"] = debugSessionId
    }
    let result = try await post("/ingestInstall", body: body)
    tracked = true
    cacheFromResult(result)
    return result
  }

  @discardableResult
  public static func setAppUserId(_ appUserId: String) async throws -> [String: Any] {
    lastAppUserId = appUserId
    var body: [String: Any] = ["appUserId": appUserId]
    if let lastAttributionId {
      body["attributionId"] = lastAttributionId
    }
    if let debugSessionId = config?.debugSessionId {
      body["debugSessionId"] = debugSessionId
    }
    return try await post("/ingestIdentify", body: body)
  }

  @discardableResult
  public static func applyCode(_ code: String) async throws -> [String: Any] {
    var body: [String: Any] = [
      "code": code,
      "platform": "IOS",
    ]
    if let lastAppUserId {
      body["appUserId"] = lastAppUserId
    }
    if let lastAttributionId {
      body["attributionId"] = lastAttributionId
    }
    if let debugSessionId = config?.debugSessionId {
      body["debugSessionId"] = debugSessionId
    }
    let result = try await post("/redeemCode", body: body)
    cacheFromResult(result)
    return result
  }

  public static func getOffer() -> TapAppLinkOffer? {
    lastOffer
  }

  @discardableResult
  public static func linkRevenueCatUser(_ appUserId: String) async throws -> [String: Any] {
    try await setAppUserId(appUserId)
  }

  @discardableResult
  public static func linkAdaptyUser(_ customerUserId: String) async throws -> [String: Any] {
    try await setAppUserId(customerUserId)
  }

  @discardableResult
  public static func linkSuperwallUser(_ appUserId: String) async throws -> [String: Any] {
    try await setAppUserId(appUserId)
  }

  @discardableResult
  public static func linkQonversionUser(_ userId: String) async throws -> [String: Any] {
    try await setAppUserId(userId)
  }

  public static func resetForTesting() {
    tracked = false
    lastAttributionId = nil
    lastAppUserId = nil
    lastOffer = nil
  }

  private static func cacheFromResult(_ result: [String: Any]) {
    if let attributionId = result["attributionId"] as? String {
      lastAttributionId = attributionId
    }
    guard let offer = result["offer"] as? [String: Any] else { return }
    lastOffer = TapAppLinkOffer(
      creatorName: offer["creatorName"] as? String ?? "",
      promoCode: offer["promoCode"] as? String,
      discountBps: offer["discountBps"] as? Int ?? 0,
      billingOfferId: offer["billingOfferId"] as? String
    )
  }

  private static func regionCode() -> String {
    if #available(iOS 16, macOS 13, *) {
      return Locale.current.region?.identifier ?? "unknown"
    }
    return Locale.current.regionCode ?? "unknown"
  }

  private static func ingestBase() throws -> URL {
    guard let config else {
      throw TapAppLinkError.notConfigured
    }
    let raw = (config.ingestUrl ?? "https://us-central1-tapapplink.cloudfunctions.net")
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard let url = URL(string: raw) else {
      throw TapAppLinkError.invalidURL
    }
    return url
  }

  private static func post(_ path: String, body: [String: Any]) async throws -> [String: Any] {
    guard let config else {
      throw TapAppLinkError.notConfigured
    }
    let url = try ingestBase().appendingPathComponent(
      path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    )
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(config.publicKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
      throw TapAppLinkError.requestFailed
    }
    return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
  }
}

public enum TapAppLinkError: Error {
  case notConfigured
  case invalidURL
  case requestFailed
}
