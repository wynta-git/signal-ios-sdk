# Signal iOS SDK — Publish Guide (SPM + CocoaPods)

The iOS SDK supports two distribution channels:
- **Swift Package Manager (SPM)** — primary, zero setup for consumers
- **CocoaPods** — secondary, for projects that haven't migrated to SPM yet

---

## Swift Package Manager

SPM distribution is entirely Git-tag based — no registry, no publish command.

### Step 1 — Bump the version

Update the version string in `SignalSDK.podspec` (keeps both channels in sync):

```ruby
s.version = '1.0.1'
```

Also update the version constant in `Sources/SignalSDK/Services/EventService.swift`:

```swift
private static let sdkVersion = "1.0.1"
```

### Step 2 — Commit and tag

```bash
git add .
git commit -m "Release 1.0.1"
git tag 1.0.1
git push origin main --tags
```

That's it. SPM consumers resolve the package via the tag automatically.

### Step 3 — Create a GitHub Release (recommended)

On GitHub, go to **Releases → Draft a new release**, select tag `1.0.1`, and add release notes. This makes it easier to browse the changelog.

---

## CocoaPods

### Prerequisites (first time only)

```bash
gem install cocoapods
pod trunk register support@signal-sdk.com 'Signal SDK' --description='Signal SDK CI'
# Check your email and click the verification link
```

### Validate the podspec before publishing

```bash
cd SignalSDK/iossdk
pod lib lint SignalSDK.podspec --allow-warnings
```

Fix any errors before proceeding.

### Publish to CocoaPods Trunk

```bash
pod trunk push SignalSDK.podspec --allow-warnings
```

Trunk propagates to the CDN within a few minutes. Verify:

```bash
pod search SignalSDK
```

---

## Consumer integration (after publish)

### SPM

In Xcode → **File → Add Package Dependencies**:
```
https://github.com/signal-sdk/ios-sdk
```
Select version rule: **Up to Next Major** → `1.0.0`

### CocoaPods

```ruby
# Podfile
pod 'SignalSDK', '~> 1.0'
```

```bash
pod install
```

---

## Version strategy

| Bump | When |
|---|---|
| Patch (`1.0.x`) | Bug fixes, no API changes |
| Minor (`1.x.0`) | New features, backwards compatible |
| Major (`x.0.0`) | Breaking API changes |

Both SPM and CocoaPods must be released at the **same version** — tag once, push podspec once.

---

## Release checklist

- [ ] Bump `s.version` in `SignalSDK.podspec`
- [ ] Bump `sdkVersion` in `EventService.swift`
- [ ] Run `pod lib lint SignalSDK.podspec --allow-warnings` — no errors
- [ ] Commit changes
- [ ] `git tag <version> && git push origin main --tags`
- [ ] `pod trunk push SignalSDK.podspec --allow-warnings`
- [ ] Verify on CocoaPods: `pod search SignalSDK`
- [ ] Create GitHub Release with changelog
