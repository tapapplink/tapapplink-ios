# Tap App Link iOS SDK

Native Swift package for creator install attribution and promo-code offers. Works without IDFA and without an App Tracking Transparency prompt.

## Install

In Xcode: **File → Add Package Dependencies** →

```
https://github.com/tapapplink/tapapplink-ios
```

Or in a `Package.swift`:

```swift
.package(url: "https://github.com/tapapplink/tapapplink-ios", from: "0.1.1")
```

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

## License

MIT
