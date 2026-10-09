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
  /// When true, logs each request, response and stored state. API keys are redacted.
  public var debugLogging: Bool

  public init(
    publicKey: String,
    environment: TapAppLinkEnvironment,
    ingestUrl: String? = nil,
    debugLogging: Bool = false
  ) {
    self.publicKey = publicKey
    self.environment = environment
    self.ingestUrl = ingestUrl
    self.debugLogging = debugLogging
  }
}

public struct TapAppLinkOffer: Sendable, Codable, Equatable {
  public var creatorName: String
  public var promoCode: String?
  public var billingOfferId: String?

  public init(
    creatorName: String,
    promoCode: String? = nil,
    billingOfferId: String? = nil
  ) {
    self.creatorName = creatorName
    self.promoCode = promoCode
    self.billingOfferId = billingOfferId
  }
}

public enum TapAppLink {
  private static var config: TapAppLinkConfig?
  private static var tracked = false
  private static var installId: String?
  private static var lastAttributionId: String?
  private static var lastAppUserId: String?
  private static var lastOffer: TapAppLinkOffer?
  private static let session = URLSession.shared
  private static let defaults = UserDefaults(suiteName: Storage.suiteName) ?? .standard

  public static func configure(_ next: TapAppLinkConfig) {
    config = next
    loadPersistedState()
    log("configure environment=\(next.environment.rawValue) key=\(redact(next.publicKey))")
    logStoredState()
  }

  @discardableResult
  public static func trackInstall() async throws -> [String: Any] {
    loadPersistedState()
    let id = ensureInstallId()

    if tracked {
      let result = skippedInstallResult()
      log("trackInstall skipped (already tracked for this install)")
      log("trackInstall returning \(debugJSON(result))")
      logStoredState()
      return result
    }

    #if canImport(UIKit)
    let deviceFamily = UIDevice.current.model.contains("iPad") ? "iPad" : "iPhone"
    #else
    let deviceFamily = "iPhone"
    #endif
    let body: [String: Any] = [
      "platform": "IOS",
      "deviceFamily": deviceFamily,
      "locale": Locale.current.identifier,
      "networkContext": regionCode(),
      "firstOpenAt": ISO8601DateFormatter().string(from: Date()),
      "installId": id,
    ]
    let result = try await post("/ingestInstall", body: body)
    tracked = true
    persistTracked(true)
    cacheFromResult(result)
    logStoredState()
    return result
  }

  @discardableResult
  public static func setAppUserId(_ appUserId: String) async throws -> [String: Any] {
    loadPersistedState()
    lastAppUserId = appUserId
    var body: [String: Any] = ["appUserId": appUserId]
    if let lastAttributionId {
      body["attributionId"] = lastAttributionId
    }
    return try await post("/ingestIdentify", body: body)
  }

  @discardableResult
  public static func applyCode(_ code: String) async throws -> [String: Any] {
    loadPersistedState()
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
    let result = try await post("/redeemCode", body: body)
    cacheFromResult(result)
    logStoredState()
    return result
  }

  public static func getOffer() -> TapAppLinkOffer? {
    loadPersistedState()
    return lastOffer
  }

  public static func getAttributionId() -> String? {
    loadPersistedState()
    return lastAttributionId
  }

  public static func getAppUserId() -> String? {
    lastAppUserId
  }

  public static func getInstallId() -> String? {
    loadPersistedState()
    return installId
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

  /// Clears in-memory and persisted install state. Use in debug builds before repeating a match test.
  public static func resetForTesting() {
    tracked = false
    installId = nil
    lastAttributionId = nil
    lastAppUserId = nil
    lastOffer = nil
    Storage.clear(defaults)
    log("resetForTesting cleared memory and UserDefaults suite \(Storage.suiteName)")
  }

  /// Seeds persisted install state for tests. Also updates in-memory mirrors.
  public static func seedPersistedStateForTesting(
    installId: String,
    tracked: Bool,
    attributionId: String? = nil,
    offer: TapAppLinkOffer? = nil
  ) {
    self.installId = installId
    self.tracked = tracked
    self.lastAttributionId = attributionId
    self.lastOffer = offer
    defaults.set(installId, forKey: Storage.installId)
    defaults.set(tracked, forKey: Storage.tracked)
    defaults.set(attributionId, forKey: Storage.attributionId)
    if let offer {
      persistOffer(offer)
    } else {
      defaults.removeObject(forKey: Storage.offer)
    }
  }

  /// Drops in-memory state while leaving UserDefaults intact, to simulate a cold launch.
  public static func simulateColdLaunchForTesting() {
    config = nil
    tracked = false
    installId = nil
    lastAttributionId = nil
    lastAppUserId = nil
    lastOffer = nil
  }

  private static func skippedInstallResult() -> [String: Any] {
    var result: [String: Any] = [
      "matched": false,
      "skipped": true,
    ]
    if let installId {
      result["installId"] = installId
    }
    if let lastAttributionId {
      result["attributionId"] = lastAttributionId
    }
    if let lastOffer {
      var offer: [String: Any] = ["creatorName": lastOffer.creatorName]
      if let promoCode = lastOffer.promoCode {
        offer["promoCode"] = promoCode
      }
      if let billingOfferId = lastOffer.billingOfferId {
        offer["billingOfferId"] = billingOfferId
      }
      result["offer"] = offer
    }
    return result
  }

  private static func ensureInstallId() -> String {
    if let installId {
      return installId
    }
    if let stored = defaults.string(forKey: Storage.installId), !stored.isEmpty {
      installId = stored
      return stored
    }
    let generated = UUID().uuidString
    installId = generated
    defaults.set(generated, forKey: Storage.installId)
    log("generated installId=\(generated)")
    return generated
  }

  private static func loadPersistedState() {
    if installId == nil {
      installId = defaults.string(forKey: Storage.installId)
    }
    if defaults.object(forKey: Storage.tracked) != nil {
      tracked = defaults.bool(forKey: Storage.tracked)
    }
    if lastAttributionId == nil {
      lastAttributionId = defaults.string(forKey: Storage.attributionId)
    }
    if lastOffer == nil, let data = defaults.data(forKey: Storage.offer) {
      lastOffer = try? JSONDecoder().decode(TapAppLinkOffer.self, from: data)
    }
  }

  private static func persistTracked(_ value: Bool) {
    defaults.set(value, forKey: Storage.tracked)
  }

  private static func persistAttributionId(_ value: String) {
    defaults.set(value, forKey: Storage.attributionId)
  }

  private static func persistOffer(_ offer: TapAppLinkOffer) {
    if let data = try? JSONEncoder().encode(offer) {
      defaults.set(data, forKey: Storage.offer)
    }
  }

  private static func cacheFromResult(_ result: [String: Any]) {
    if let attributionId = result["attributionId"] as? String {
      lastAttributionId = attributionId
      persistAttributionId(attributionId)
    }
    guard let offer = result["offer"] as? [String: Any] else { return }
    let next = TapAppLinkOffer(
      creatorName: offer["creatorName"] as? String ?? "",
      promoCode: offer["promoCode"] as? String,
      billingOfferId: offer["billingOfferId"] as? String
    )
    lastOffer = next
    persistOffer(next)
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

    log("request \(path) url=\(url.absoluteString) body=\(debugJSON(body))")
    log("request Authorization=Bearer \(redact(config.publicKey))")

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
      let status = (response as? HTTPURLResponse)?.statusCode ?? -1
      log("response \(path) status=\(status) failed")
      throw TapAppLinkError.requestFailed
    }

    let parsed = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    log("response \(path) status=\(http.statusCode) body=\(debugJSON(parsed))")
    return parsed
  }

  private static func logStoredState() {
    let offerSummary: String
    if let lastOffer {
      offerSummary =
        "creatorName=\(lastOffer.creatorName) promoCode=\(lastOffer.promoCode ?? "nil") " +
        "billingOfferId=\(lastOffer.billingOfferId ?? "nil")"
    } else {
      offerSummary = "nil"
    }
    log(
      "storedState installId=\(installId ?? "nil") tracked=\(tracked) " +
        "attributionId=\(lastAttributionId ?? "nil") " +
        "appUserId=\(lastAppUserId ?? "nil") offer=(\(offerSummary))"
    )
  }

  private static func log(_ message: String) {
    guard config?.debugLogging == true else { return }
    print("[TapAppLink] \(message)")
  }

  private static func redact(_ key: String) -> String {
    guard key.count > 8 else { return "***" }
    return "\(key.prefix(4))...\(key.suffix(4))"
  }

  private static func debugJSON(_ value: [String: Any]) -> String {
    guard
      let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
      let string = String(data: data, encoding: .utf8)
    else {
      return String(describing: value)
    }
    return string
  }

  private enum Storage {
    static let suiteName = "com.tapapplink.sdk"
    static let installId = "tapapplink.installId"
    static let tracked = "tapapplink.tracked"
    static let attributionId = "tapapplink.attributionId"
    static let offer = "tapapplink.offer"

    static func clear(_ defaults: UserDefaults) {
      defaults.removeObject(forKey: installId)
      defaults.removeObject(forKey: tracked)
      defaults.removeObject(forKey: attributionId)
      defaults.removeObject(forKey: offer)
    }
  }
}

public enum TapAppLinkError: Error {
  case notConfigured
  case invalidURL
  case requestFailed
}
