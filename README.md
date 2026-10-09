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
.package(url: "https://github.com/tapapplink/tapapplink-ios", from: "0.3.0")
```

Pin to a released semver tag such as `0.3.0`. See [CONTRIBUTING.md](CONTRIBUTING.md) for how CI verifies tags and publishes GitHub Releases.

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

try await TapAppLink.applyCode("SARAH10")
```

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
