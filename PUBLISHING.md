# Signal iOS SDK — Publish Guide (Public Distribution)

The iOS SDK supports two distribution channels, both **public**, matching how MoEngage
ships their iOS SDK (`github.com/moengage/apple-sdk`, `pod 'MoEngage-iOS-SDK'`, public SPM):
- **Swift Package Manager (SPM)** — primary, zero setup for consumers beyond a public
  GitHub URL
- **CocoaPods** — secondary, via the public CocoaPods Trunk, for projects that haven't
  migrated to SPM yet

This mirrors the Android SDK's move to Maven Central (see `../androidsdk/PUBLISHING.md`).

> **Real repo (as of this doc)**: `github.com/wynta-git/signal-ios-sdk` — **public**,
> `1.0.0` tagged and released on both SPM and CocoaPods Trunk (owner `Wynta Software
> <support@wynta.com>`). Verified clean (correct file scope, no secrets) via a fresh
> clone both before and after flipping it public — see `../androidsdk/PUBLISHING.md`'s
> troubleshooting section for why that verification step exists.

---

## Why public, and what that costs

- **Credential flow**: `clientId` / `clientSecret` are supplied per-app at `initSDK(config:)`
  — same model as MoEngage's per-app API key. Not baked into the binary, so publishing
  source publicly doesn't leak any one client's secret.
- **Environment routing**: the `QA_` prefix convention and the literal QA/PROD base URLs
  (`qa-app.fozilpartners.com`, `api.wynta.com`) are hardcoded constants in `SignalSDK.swift`.
  Going public makes both hostnames world-visible, permanently — same accepted tradeoff as
  the Android SDK.
- **No source-hiding equivalent to Android's R8 minification**: SPM and CocoaPods both
  distribute plain Swift source that the consumer's own toolchain compiles — there's no
  "ship an obfuscated binary" step short of switching to a precompiled closed-source
  XCFramework, which MoEngage's iOS SDK doesn't do either (their `apple-sdk` repo is plain
  Swift source, confirmed from the public GitHub repo). We're matching that, not going
  further: source ships readable, same as it always would for any SPM/CocoaPods package.
- **Event/trait schema**: the shape of `IdentifyRequest`, `TrackEvent`, and the
  `PlayerTraits` → snake_case mapping becomes visible the same way REST API shapes are for
  any public SDK — this is the same tradeoff MoEngage accepts for their integration
  contract.
- **Cross-platform parity**: matches the Android SDK's public API 1:1, so going public here
  keeps both platforms consistent rather than leaving iOS as the weaker-gated link.

---

## Two-tier repo model

- **Source of truth / day-to-day development**: this folder (`PAM/SignalSDK/iossdk`),
  inside the `pam` Bitbucket repo, alongside the Android and React Native SDKs. Keep coding
  here exactly as you do now — nothing changes about day-to-day work.
- **Release mirror**: a dedicated **public** GitHub repo — e.g.
  `github.com/wynta-git/signal-ios-sdk` — containing **only** this folder's contents at its
  root (`Package.swift`, `Sources/`, `SignalSDK.podspec`, `LICENSE`).

This split exists because SPM has no central registry: it resolves a package straight from
a git URL + tag, and it requires `Package.swift` to sit at that repo's **root**. A consumer
can't point SPM at a subfolder of the `pam` monorepo — it needs its own repo, and that repo
now needs to be public for the install experience to have zero auth step.

Only when you deliberately publish a version does a snapshot of this folder move to the
public repo. Ordinary commits to `pam` never affect consumers until that happens, and
nothing in the private `pam` monorepo (backend implementation, other services, docs)
crosses into the public repo — only this SDK folder's contents do.

---

## One-time setup (already done for this SDK — kept here for the next maintainer)

1. **Create the repo private first, verify, then flip to public** — this is the one
   lesson carried over from the Android SDK's publishing mistake (see
   `../androidsdk/PUBLISHING.md`): a `git subtree split --prefix=SignalSDK/iossdk` was
   verified locally (commit count, file scope, secret scan) *before* ever pushing, pushed
   to `github.com/wynta-git/signal-ios-sdk` while **private**, then re-verified via a
   fresh clone of the actual GitHub repo. Only flip to public after that fresh-clone
   verification passes — never rely on the local check alone once something's been pushed.
2. **CocoaPods Trunk account** — registered as `Wynta Software <support@wynta.com>`. To
   add another maintainer's machine as a valid publishing session:
   ```bash
   pod trunk register support@wynta.com 'Wynta Software' --description='<your machine>'
   ```
   Needs someone with access to that inbox to click the confirmation link CocoaPods sends.
   Check current sessions/registered pods any time with `pod trunk me`.

---

## Publishing a new version

### Step 1 — Bump the version

Update the version string in `SignalSDK.podspec` (keeps both channels in sync):

```ruby
s.version = '1.0.1'
```

Also update the version constant in `Sources/SignalSDK/Services/EventService.swift`:

```swift
private static let sdkVersion = "1.0.1"
```

### Step 2 — Sync this folder to the public repo

`iossdk` is a subfolder of the `pam` monorepo, not its own repo, so a plain `git push`
won't work — you need to push only this folder's contents to the public repo's root.
This is the exact process used for every release so far:

```bash
cd PAM   # repo root

# Rebuild the split branch fresh each release — don't reuse an old one, it won't
# include your latest commits
git branch -D clean-ios-sdk-export 2>/dev/null
git subtree split --prefix=SignalSDK/iossdk -b clean-ios-sdk-export

# Verify locally BEFORE pushing anywhere — commit count, file scope, secret scan
git log --oneline clean-ios-sdk-export
git log --name-only --pretty=format: clean-ios-sdk-export | sort -u | grep -v "^$" | \
  grep -viE "^(INTEGRATION\.md|PUBLISHING\.md|Package\.swift|SignalSDK\.podspec|LICENSE|Sources/|\.swiftpm/)"
  # ^ must be blank — anything printed here is a file that doesn't belong in the public repo
git log clean-ios-sdk-export -p 2>/dev/null | grep -niE "private_key|BEGIN PRIVATE KEY|mongodb://[a-zA-Z0-9_]+:"
  # ^ must be blank — anything printed here is a leaked secret, stop and investigate

# Only once both checks are clean, push it
git push https://github.com/wynta-git/signal-ios-sdk.git clean-ios-sdk-export:main
```

### Step 2.5 — Re-verify from a fresh clone of the actual GitHub repo

Don't skip this — the local branch and what's actually reachable on GitHub can differ
(this is exactly what went wrong with the Android SDK). Clone fresh and repeat both
checks from Step 2 against the real remote:

```bash
rm -rf /tmp/ios_sdk_verify
git clone https://github.com/wynta-git/signal-ios-sdk.git /tmp/ios_sdk_verify
cd /tmp/ios_sdk_verify
git ls-remote https://github.com/wynta-git/signal-ios-sdk.git   # check for unexpected tags/branches
git log --all --name-only --pretty=format: | sort -u | grep -v "^$" | \
  grep -viE "^(INTEGRATION\.md|PUBLISHING\.md|Package\.swift|SignalSDK\.podspec|LICENSE|Sources/|\.swiftpm/)"
git log --all -p 2>/dev/null | grep -niE "private_key|BEGIN PRIVATE KEY|mongodb://[a-zA-Z0-9_]+:"
```

### Step 3 — Tag and push

```bash
git tag 1.0.1
git push origin main --tags
```

### Step 4 — Lint and push to CocoaPods Trunk

```bash
cd PAM/SignalSDK/iossdk
pod lib lint SignalSDK.podspec --allow-warnings
pod trunk push SignalSDK.podspec --allow-warnings
```

This publishes to the public CocoaPods CDN — visible via `pod search SignalSDK` and
installable by anyone, same as MoEngage's `MoEngage-iOS-SDK` pod. There's no un-publish;
`pod trunk delete` only removes a single bad version, it doesn't pull the SDK off the CDN
retroactively for consumers who already resolved it.

### Step 5 — Record the release

GitHub Releases works here (unlike the old Bitbucket flow) — tag push from Step 3 is
enough for SPM to resolve it, but also add an entry to `CHANGELOG.md` at the repo root so
consumers have something to read when bumping their pinned version.

---

## SPM — no extra registry step

SPM has no separate publish action beyond the tag push in Step 3 — it resolves directly
from the public git repo + tag, same as CocoaPods' `:git` source did in the old private
model, just without credentials now that the repo is public.

---

## Consumer integration (after publish)

### SPM

In Xcode → **File → Add Package Dependencies**:
```
https://github.com/wynta-git/signal-ios-sdk.git
```
No credential prompt — the repo is public. Select version rule: **Up to Next Major** →
`1.0.1`.

### CocoaPods

```ruby
pod 'SignalSDK', '~> 1.0.1'
```

```bash
pod install
```

Resolves from the public CocoaPods Trunk CDN — no `:git`/`:tag` source override needed
anymore, same as any other public pod.

---

## Version strategy

| Bump | When |
|---|---|
| Patch (`1.0.x`) | Bug fixes, no API changes |
| Minor (`1.x.0`) | New features, backwards compatible |
| Major (`x.0.0`) | Breaking API changes |

Both SPM and CocoaPods must be released at the **same version** — one sync + one tag +
one trunk push covers both.

---

## Release checklist

- [ ] Bump `s.version` in `SignalSDK.podspec`
- [ ] Bump `sdkVersion` in `EventService.swift`
- [ ] Run `pod lib lint SignalSDK.podspec --allow-warnings` locally — no errors
- [ ] Commit changes in `pam` as usual
- [ ] Rebuild the split branch fresh and verify it locally (commit count, file scope,
      secret scan — Step 2)
- [ ] Push to the public repo, then fresh-clone and re-verify from the real remote
      (Step 2.5) — don't skip this even though it feels redundant with the local check
- [ ] Tag the public repo (`git tag <version> && git push origin main --tags`)
- [ ] `pod trunk push SignalSDK.podspec --allow-warnings`
- [ ] Add an entry to `CHANGELOG.md` in the public repo
- [ ] Verify the new version resolves via a clean `pod install` and SPM add-package

---

## Appendix — private-repo distribution (superseded, kept for reference)

Before this SDK went public, versions were synced to a private Bitbucket repo and
CocoaPods referenced it via `:git => '...', :tag => '...'` instead of the public Trunk —
no `pod trunk register`/`pod trunk push` involved, consumers needed Bitbucket read access
or an SSH deploy key. That mechanics can be restored from this file's git history if this
SDK is ever pulled back to private-only distribution.
