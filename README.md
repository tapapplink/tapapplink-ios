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
.package(url: "https://github.com/tapapplink/tapapplink-ios", from: "0.2.0")
```

Pin to a released semver tag such as `0.2.0`. See [CONTRIBUTING.md](CONTRIBUTING.md) for how CI verifies tags and publishes GitHub Releases.

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

`trackInstall()` is safe on every launch — it only records once per install. Call `resetForTesting()` in debug builds before repeating a match test on the same install.

Purchases are attributed through billing webhooks. Leave out a client `trackPurchase` call.

## Development

```bash
swift build
swift test
swiftlint lint --strict --config .swiftlint.yml
```

CI runs those checks on every pull request and push to `main`, plus an iOS Simulator `xcodebuild`. Tag pushes that match semver also create a GitHub Release. Details are in [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT
