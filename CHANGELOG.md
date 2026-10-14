# Changelog

## 0.3.3

- **Fixed:** `setAppUserId` posted `/ingestIdentify` on every call, so apps that link the billing user id from several places (for example Keep Maps) could fire it three times per launch. 0.3.3 skips when the id matches the last successfully identified value (persisted like `trackInstall`), and coalesces concurrent identical calls into one request. A different id still posts.
- Add typed `TapAppLinkRedeemResult` from `applyCode` with optional `codeMatches` and `offer.creatorName` (matches server redeem response fields when already attributed).
- Send `X-TapAppLink-SDK-Version: 0.3.3` on all requests.

## 0.3.2

- **Fixed:** retrying `applyCode` after a timeout could count an install twice. 0.3.2 sends a request ID so the server recognises the retry. No code changes needed.

## 0.3.1

- **Fixed:** Android and React Native 0.3.0 could return an error from `applyCode()` as if it were a normal result, so an app could show a code as applied when it wasn't. Upgrade to 0.3.1, which raises a typed error for unknown, inactive and wrong-environment codes. iOS and Flutter 0.3.0 threw a generic error, and 0.3.1 makes it typed.
- Map redeem failures to `TapAppLinkRedeemError` (`unknownCode`, `inactiveCode`, `wrongEnvironment`, `network`, `other(status:message:)`), including legacy 404 bodies and the newer 410/400 statuses.
- Send `X-TapAppLink-SDK-Version: 0.3.1` on every ingest request so the server can return distinct redeem statuses.

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
