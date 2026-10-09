import Foundation

/// Persists the in-flight redeem `requestId` so retries of the same normalised
/// code reuse one UUID until a definitive server response.
enum RedeemAttemptStore {
  struct Pending: Codable, Equatable, Sendable {
    var normalizedCode: String
    var requestId: String
  }

  static let storageKey = "tapapplink.pendingRedeem"

  /// Uppercase, strip non-alphanumerics, max 24 characters.
  static func normalizeCode(_ code: String) -> String {
    let filtered = code.uppercased().filter { $0.isLetter || $0.isNumber }
    return String(filtered.prefix(24))
  }

  static func load(from defaults: UserDefaults) -> Pending? {
    guard let data = defaults.data(forKey: storageKey) else { return nil }
    return try? JSONDecoder().decode(Pending.self, from: data)
  }

  static func save(_ pending: Pending, to defaults: UserDefaults) {
    guard let data = try? JSONEncoder().encode(pending) else { return }
    defaults.set(data, forKey: storageKey)
  }

  static func clear(_ defaults: UserDefaults) {
    defaults.removeObject(forKey: storageKey)
  }
}
