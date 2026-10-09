# Changelog

## 0.3.0

- Persist install id, tracked flag, attribution id and offer in `UserDefaults`, so `trackInstall()` posts `/ingestInstall` only once per install and later launches return the stored attribution and offer without a network call.
- Send a stable `installId` (UUID string) in the `/ingestInstall` body for server-side dedupe.
- Add `PrivacyInfo.xcprivacy` (UserDefaults reason CA92.1, no tracking, collected data types the SDK sends).
- Add opt-in `debugLogging` on `TapAppLinkConfig` that logs requests, responses and stored state with the API key redacted.

## 0.2.0

- Remove `discountBps` from `TapAppLinkOffer`. Present `billingOfferId` on the paywall.

## 0.1.1

- Remove unused `debugSessionId` from `configure()`. The sandbox debugger attaches via the QR link or code watch.

## 0.1.0

- First public Swift Package release.
