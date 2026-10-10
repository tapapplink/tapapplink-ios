# Tap App Link iOS SDK

Native Swift package for creator install attribution and promo-code offers. Works without IDFA and without an App Tracking Transparency prompt.

## Install

Distributed via Swift Package Manager using git tags (no separate registry publish).

In Xcode: **File → Add Package Dependencies** →

```
https://github.com/tapapplink/tapapplink-ios
```

Or in a `Package.swift`:

```swift
.package(url: "https://github.com/tapapplink/tapapplink-ios", from: "0.3.2")
```

Pin to a released semver tag such as `0.3.2`. See [CONTRIBUTING.md](CONTRIBUTING.md) for how CI verifies tags and publishes GitHub Releases.

## Usage

```swift
import TapAppLink

TapAppLink.configure(.init(
  publicKey: "etk_live_…",
  environment: .production
))

try await TapAppLink.trackInstall()
try await TapAppLink.setAppUserId(Purchases.shared.appUserID)

if let offer = TapAppLink.getOffer() {
  // Present the discounted billing offer
}

let code = "SARAH10"
do {
  let result = try await TapAppLink.applyCode(code)
  let alreadyAttributed = result["alreadyAttributed"] as? Bool ?? false
  let offer = result["offer"] as? [String: Any]
  let offerLine: String? = {
    guard let name = offer?["creatorName"] as? String, !name.isEmpty else { return nil }
    if let promo = offer?["promoCode"] as? String, !promo.isEmpty {
      return "\(name) · \(promo)"
    }
    return name
  }()

  if alreadyAttributed {
    // Title: "You're all set"
    // Hide the code the customer typed.
    // Show offerLine if present.
  } else {
    // Title: "Code applied"
    // Show the code, plus offerLine if present.
  }
} catch TapAppLinkRedeemError.unknownCode {
  // Title: "We don't recognise that code. Check it and try again."
  // Hint: "Codes aren't case sensitive."
} catch TapAppLinkRedeemError.inactiveCode {
  // Title: "This code is no longer active."
  // Hint: "You can still subscribe at the regular price."
} catch TapAppLinkRedeemError.wrongEnvironment {
  // Same customer-facing copy as unknownCode. Never auto-retry.
  // Title: "We don't recognise that code. Check it and try again."
  // Hint: "Codes aren't case sensitive."
  // Developer-only (never show to customers):
  // TapAppLinkRedeemError.wrongEnvironmentDeveloperWarning
  // → "This code belongs to the other environment (Sandbox or Production). Check your API key."
} catch TapAppLinkRedeemError.network {
  // Network/timeout only: retry applyCode once with the same code.
  // Do not auto-retry unknown, inactive or wrongEnvironment.
  do {
    let result = try await TapAppLink.applyCode(code)
    // Handle success the same way as the first attempt (alreadyAttributed / offerLine).
    _ = result // replace with the success UI above
  } catch {
    // N6: "We couldn't check your code. Check your connection and try again."
    // Show a Try again button.
  }
} catch let TapAppLinkRedeemError.other(status, message) {
  // Same customer-facing copy as N6 (no automatic retry).
  // Log status and message for developers only.
  print("applyCode failed status=\(status) message=\(message)")
}
```

From 0.3.2, that automatic network retry is safe because the SDK reuses its request ID, so the server won't count the install twice.

Show success UI only on a real success result from `applyCode`. Do not treat an error as applied.

`trackInstall()` is safe on every launch: the SDK persists an install id, the tracked flag, the attribution id and the offer in `UserDefaults`, and only posts `/ingestInstall` once per install. Later launches return the stored attribution and offer without a network call. Call `resetForTesting()` in debug builds before repeating a match test on the same install.

Opt into request logging with `debugLogging: true` on `TapAppLinkConfig`. Logs include each request, response and stored state, and redact the API key.

Purchases are attributed through billing webhooks. Leave out a client `trackPurchase` call.

## Privacy

The package ships a `PrivacyInfo.xcprivacy` manifest: no tracking, UserDefaults access under reason CA92.1, and declarations for the data types sent to the ingest API (device id / install id, user id, product interaction, coarse location / region, and other diagnostic fields such as platform and locale).

## Development

```bash
swift build
swift test
swiftlint lint --strict --config .swiftlint.yml
```

CI runs those checks on every pull request and push to `main`, plus an iOS Simulator `xcodebuild`. Tag pushes that match semver also create a GitHub Release. Details are in [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT
