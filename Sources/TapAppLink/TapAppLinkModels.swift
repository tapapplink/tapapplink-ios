import Foundation

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

/// Success body from `/redeemCode`. New fields from the server are optional so
/// older clients keep compiling.
public struct TapAppLinkRedeemResult: Sendable, Equatable {
  public var attributionId: String?
  public var alreadyAttributed: Bool?
  /// True when the submitted code matches the attributed creator offer.
  public var codeMatches: Bool?
  public var offer: Offer?

  public struct Offer: Sendable, Equatable {
    public var creatorName: String?
    public var promoCode: String?
    public var billingOfferId: String?

    public init(
      creatorName: String? = nil,
      promoCode: String? = nil,
      billingOfferId: String? = nil
    ) {
      self.creatorName = creatorName
      self.promoCode = promoCode
      self.billingOfferId = billingOfferId
    }
  }

  public init(
    attributionId: String? = nil,
    alreadyAttributed: Bool? = nil,
    codeMatches: Bool? = nil,
    offer: Offer? = nil
  ) {
    self.attributionId = attributionId
    self.alreadyAttributed = alreadyAttributed
    self.codeMatches = codeMatches
    self.offer = offer
  }

  static func from(dictionary: [String: Any]) -> TapAppLinkRedeemResult {
    var offer: Offer?
    if let raw = dictionary["offer"] as? [String: Any] {
      offer = Offer(
        creatorName: raw["creatorName"] as? String,
        promoCode: raw["promoCode"] as? String,
        billingOfferId: raw["billingOfferId"] as? String
      )
    }
    return TapAppLinkRedeemResult(
      attributionId: dictionary["attributionId"] as? String,
      alreadyAttributed: dictionary["alreadyAttributed"] as? Bool,
      codeMatches: dictionary["codeMatches"] as? Bool,
      offer: offer
    )
  }
}
