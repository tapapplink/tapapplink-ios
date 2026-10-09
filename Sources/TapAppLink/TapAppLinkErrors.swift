import Foundation

public enum TapAppLinkError: Error, Equatable, Sendable {
  case notConfigured
  case invalidURL
  case requestFailed
}

/// Typed errors from `applyCode(_:)`.
public enum TapAppLinkRedeemError: Error, Equatable, Sendable {
  case unknownCode
  case inactiveCode
  case wrongEnvironment
  case network
  case other(status: Int, message: String)

  /// Developer-only warning for `wrongEnvironment`. Never show this to customers.
  public static let wrongEnvironmentDeveloperWarning =
    "This code belongs to the other environment (Sandbox or Production). Check your API key."

  static func from(status: Int, body: [String: Any]) -> TapAppLinkRedeemError {
    let errorCode = body["error"] as? String
    let message = (body["message"] as? String)
      ?? HTTPURLResponse.localizedString(forStatusCode: status)

    switch errorCode {
    case "unknown_code":
      return .unknownCode
    case "inactive_code":
      return .inactiveCode
    case "wrong_environment":
      return .wrongEnvironment
    default:
      break
    }

    switch status {
    case 404:
      return .unknownCode
    case 410:
      return .inactiveCode
    case 400 where errorCode == "wrong_environment":
      return .wrongEnvironment
    default:
      return .other(status: status, message: message)
    }
  }
}
