# Tap App Link iOS SDK

Native iOS / macOS client for Tap App Link attribution.

## Install

In Xcode: File → Add Package Dependencies → [https://github.com/KennyYe/tapapplink-ios](https://github.com/KennyYe/tapapplink-ios)

```swift
import TapAppLink

TapAppLink.configure(.init(
  publicKey: "etk_live_…",
  environment: .production
))

try await TapAppLink.trackInstall()
try await TapAppLink.setAppUserId(Purchases.shared.appUserID)
```

## License

MIT
