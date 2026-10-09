# Contributing

Thanks for helping improve the Tap App Link iOS SDK.

## Development

Requirements:

- Xcode 15 or newer (Swift 5.9+)
- SwiftLint (`brew install swiftlint`)

Clone the repo, then:

```bash
swift build
swift test
swiftlint lint --strict --config .swiftlint.yml
```

To exercise an iOS Simulator build locally:

```bash
xcodebuild \
  -scheme TapAppLink \
  -destination 'generic/platform=iOS Simulator' \
  build
```

## Continuous integration

Every pull request and every push to `main` runs:

1. SwiftLint
2. `swift build` / `swift test` on macOS
3. An `xcodebuild` build for a generic iOS Simulator destination

## Releasing (SPM, tag-based)

This package is distributed only through Swift Package Manager using git tags. There is no separate package registry publish step.

1. Update `CHANGELOG.md` with a `## X.Y.Z` section.
2. Merge the release changes to `main`.
3. Create and push an annotated semver tag (with or without a `v` prefix; existing releases use `X.Y.Z`):

   ```bash
   git tag -a X.Y.Z -m "Release X.Y.Z"
   git push origin X.Y.Z
   ```

4. The **Release** workflow verifies the tag against the changelog, runs the same CI checks, and creates a GitHub Release.

Consumers depend on the tag like this:

```swift
.package(url: "https://github.com/tapapplink/tapapplink-ios", from: "X.Y.Z")
```

## Pull requests

- Keep changes focused; do not mix unrelated refactors with feature work.
- Prefer Australian English in user-facing docs (`organise`, `behaviour`, and so on).
- Do not change SDK behaviour unless the PR is explicitly about that change.
