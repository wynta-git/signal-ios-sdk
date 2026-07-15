# Signal iOS SDK — Integration Guide

This guide covers everything an iOS application needs to integrate the Signal SDK: installation via SPM or CocoaPods, initialization, user identity, event tracking, and lifecycle events.

---

## Table of Contents

1. [Installation](#1-installation)
   - [Swift Package Manager](#11-swift-package-manager-recommended)
   - [CocoaPods](#12-cocoapods)
2. [Initialization](#2-initialization)
3. [User Identity](#3-user-identity)
   - [Anonymous (pre-login)](#31-anonymous-pre-login)
   - [After login](#32-after-login)
   - [Updating traits](#33-updating-traits)
   - [Logout](#34-logout)
4. [Event Tracking](#4-event-tracking)
5. [Automatic Lifecycle Events](#5-automatic-lifecycle-events)
6. [Full Lifecycle Example](#6-full-lifecycle-example)
7. [API Reference](#7-api-reference)

---

## 1. Installation

There are two ways to install this SDK — **Swift Package Manager (SPM)** and
**CocoaPods**. They both do the same thing (pull the SDK's code into your project); pick
whichever matches how your project already installs its other dependencies. If you're not
sure, look at your project: if you see a `Podfile`, use CocoaPods; otherwise use SPM.

**You can also mix the two** — if your app already uses CocoaPods for everything else
(e.g. Firebase, MoEngage), you don't have to convert the whole project just to add this
SDK. You can add `SignalSDK` via SPM on its own, right alongside your existing CocoaPods
setup, with zero changes to anything else. See the note at the end of this section.

### 1.1 Swift Package Manager (recommended)

In Xcode:

1. Open your project. **If your project already uses CocoaPods**, open the
   **`.xcworkspace`** file (not the `.xcodeproj`) — CocoaPods generates this file, and it's
   the one you should always have open once CocoaPods is involved.
2. Go to the menu bar: **File → Add Package Dependencies...**
3. A dialog box appears with a search field top-right. Paste in this URL and press Enter:
   ```
   https://github.com/wynta-git/signal-ios-sdk
   ```
4. Xcode will find the package and show version options. Leave it on the default
   **"Up to Next Major Version"**, starting from `1.0.0`, then click **Add Package**.
5. A second dialog asks which target(s) to add `SignalSDK` to. Check the box for your
   main app target (e.g. the same target your app icon/name is under — for this project,
   that's **TajRummy**). Click **Add Package** again to finish.

That's it — no terminal commands needed for this path. Xcode downloads and builds the SDK
automatically the next time you build your app.

For a Swift Package (library) target instead of an app, add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/wynta-git/signal-ios-sdk", from: "1.0.0")
],
targets: [
    .target(name: "YourApp", dependencies: ["SignalSDK"])
]
```

### 1.2 CocoaPods

1. Open your project's `Podfile` in any text editor (it's a plain text file, usually at
   your project's root, next to the `.xcodeproj`).
2. Add this line inside your app's `target` block (near your other `pod '...'` lines):
   ```ruby
   pod 'SignalSDK', '~> 1.0'
   ```
3. Save the file, then open a terminal in that same folder and run:
   ```bash
   pod install
   ```
4. Once it finishes, close Xcode if it's open, and from then on always open the
   **`.xcworkspace`** file — not the `.xcodeproj`. CocoaPods creates the `.xcworkspace`
   specifically to include both your app and its pods; opening the `.xcodeproj` directly
   will be missing the pods and fail to build.

### Using both at once (CocoaPods for everything else, SPM just for this SDK)

This is a completely normal, well-supported setup — you don't need to pick only one for
the whole project. If your `Podfile` already lists other pods (Firebase, MoEngage, etc.),
just follow the SPM steps above (1.1) to add `SignalSDK` specifically, making sure you open
the `.xcworkspace` (already created by your existing CocoaPods setup) before adding the
package. Running `pod install` again later for your other pods won't remove or conflict
with the SPM package — they're managed independently.

---

## 2. Initialization

Call `SignalSDK.shared.initSDK(config:)` once from `AppDelegate.application(_:didFinishLaunchingWithOptions:)` or your `@main` App struct's `init()`. Never call it from a `UIViewController` — you'd re-initialize on every screen.

### AppDelegate (UIKit)

```swift
import SignalSDK

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        SignalSDK.shared.initSDK(config: SignalConfig(
            clientId:     "YOUR_CLIENT_ID",
            clientSecret: "YOUR_CLIENT_SECRET",
            debug:        true   // set false in production
        ))

        return true
    }
}
```

### SwiftUI App struct

```swift
import SwiftUI
import SignalSDK

@main
struct MyApp: App {

    init() {
        SignalSDK.shared.initSDK(config: SignalConfig(
            clientId:     "YOUR_CLIENT_ID",
            clientSecret: "YOUR_CLIENT_SECRET",
            debug:        true
        ))
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

**What `initSDK` does:**
- Stores credentials in memory
- Creates a stable session ID for this cold launch
- Registers `NotificationCenter` observers for foreground/background/terminate lifecycle events

After `initSDK`, always call `setIdentity` to attach a user ID before tracking events.

---

## 3. User Identity

Identity tells the SDK **who is using the app**. Maintain one active identity at a time — anonymous before login, real player ID after.

### 3.1 Anonymous (pre-login)

Call `setIdentity` right after `initSDK` with an anonymous UUID:

```swift
SignalSDK.shared.setIdentity(
    IdentityPayload(userId: "anon-\(UUID().uuidString)")
) { response in
    // runs on main thread
    if response.success {
        // sdk_init + session_started + app_opened auto-tracked
    }
}
```

### 3.2 After login

```swift
SignalSDK.shared.setIdentity(
    IdentityPayload(
        userId: "ply_776192",
        traits: PlayerTraits(
            email:            "player@example.com",
            firstName:        "Alex",
            lastName:         "Smith",
            dateOfBirth:      "1990-04-15",
            country:          "MT",
            currency:         "EUR",
            language:         "en",
            kycStatus:        "pending",
            vipLevel:         "bronze",
            accountStatus:    "active",
            registrationDate: "2026-05-18T14:38:00.000Z",
            brandId:          "brand_01"
        )
    )
)
```

### 3.3 Updating traits

```swift
// KYC approved
SignalSDK.shared.setIdentity(IdentityPayload(
    traits: PlayerTraits(kycStatus: "approved")
))

// VIP upgrade
SignalSDK.shared.setIdentity(IdentityPayload(
    traits: PlayerTraits(vipLevel: "gold")
))

// Remove a trait
SignalSDK.shared.setIdentity(IdentityPayload(
    unsetTraits: ["referral_code"]
))

// Custom fields
SignalSDK.shared.setIdentity(IdentityPayload(
    traits: PlayerTraits(custom: ["preferred_sport": "football"])
))
```

### 3.4 Logout

```swift
SignalSDK.shared.sendEvent("logout")
SignalSDK.shared.clearIdentity()
// Re-identify with a new anonymous UUID so events can still be tracked
SignalSDK.shared.setIdentity(IdentityPayload(userId: "anon-\(UUID().uuidString)"))
```

---

## 4. Event Tracking

```swift
SignalSDK.shared.sendEvent(
    "deposit_success",
    properties: [
        "amount":         100,
        "currency":       "EUR",
        "transaction_id": "txn_abc123"
    ]
) { response in
    print("tracked: \(response.success)")
}
```

The completion is optional — fire and forget is fine:

```swift
SignalSDK.shared.sendEvent("screen_view", properties: ["screen_name": "Home"])
```

### Common events

```swift
// Screen view
SignalSDK.shared.sendEvent("screen_view", properties: ["screen_name": "Home"])

// Button tap
SignalSDK.shared.sendEvent("button_tap", properties: [
    "button_id": "deposit_cta", "screen": "Wallet"
])

// Game started
SignalSDK.shared.sendEvent("game_started", properties: [
    "game_id":   "slots_001",
    "game_name": "Lucky Spin",
    "category":  "slots"
])

// Deposit
SignalSDK.shared.sendEvent("deposit_success", properties: [
    "amount":         100,
    "currency":       "EUR",
    "transaction_id": "txn_abc123"
])

// Bonus claimed
SignalSDK.shared.sendEvent("bonus_claimed", properties: [
    "bonus_id":   "welcome_bonus",
    "bonus_type": "deposit_match"
])
```

---

## 5. Automatic Lifecycle Events

The SDK automatically tracks these events — no code needed:

| Event | When fired |
|---|---|
| `sdk_init` | First `setIdentity` call after `initSDK` |
| `session_started` | First `setIdentity` call after `initSDK` |
| `app_opened` | First `setIdentity` call after `initSDK` |
| `app_foreground` | App returns from background (`willEnterForeground`) |
| `app_background` | App goes to background (`didEnterBackground`) |
| `session_ended` | App goes to background |
| `app_terminated` | App is about to terminate (`willTerminate` — best-effort, not fired on force-quit) |

> `app_foreground` is fired via `willEnterForegroundNotification`, which only fires when returning from background — **not** on cold launch. Cold launch is covered by `app_opened`.

---

## 6. Full Lifecycle Example

```swift
// AppDelegate.swift
import SignalSDK

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        SignalSDK.shared.initSDK(config: SignalConfig(
            clientId:     "YOUR_CLIENT_ID",
            clientSecret: "YOUR_CLIENT_SECRET",
            debug:        false
        ))

        // Set anonymous identity immediately
        SignalSDK.shared.setIdentity(IdentityPayload(userId: "anon-\(UUID().uuidString)")) { _ in
            SignalSDK.shared.sendEvent("screen_view", properties: ["screen_name": "Splash"])
        }

        return true
    }
}


// --- In your login flow ---

func onLoginSuccess(player: Player) {
    SignalSDK.shared.setIdentity(IdentityPayload(
        userId: player.id,
        traits: PlayerTraits(
            email:         player.email,
            firstName:     player.firstName,
            country:       player.country,
            currency:      player.currency,
            accountStatus: "active"
        )
    ))
    SignalSDK.shared.sendEvent("login_success", properties: ["method": "email"])
}


// --- When KYC is approved ---

func onKycApproved() {
    SignalSDK.shared.setIdentity(IdentityPayload(
        traits: PlayerTraits(kycStatus: "approved")
    ))
    SignalSDK.shared.sendEvent("kyc_approved")
}


// --- In your logout flow ---

func onLogout() {
    SignalSDK.shared.sendEvent("logout")
    SignalSDK.shared.clearIdentity()
    SignalSDK.shared.setIdentity(IdentityPayload(userId: "anon-\(UUID().uuidString)"))
}
```

---

## 7. API Reference

### `SignalSDK.shared.initSDK(config:)`

| Parameter | Type | Required | Description |
|---|---|---|---|
| `config.clientId` | `String` | Yes | Your Signal client ID |
| `config.clientSecret` | `String` | Yes | Your Signal client secret |
| `config.debug` | `Bool` | No | Enable console logging (default: `false`) |

---

### `SignalSDK.shared.setIdentity(_:completion:)`

| Parameter | Type | Description |
|---|---|---|
| `payload.userId` | `String?` | Player ID or anonymous UUID |
| `payload.anonymousId` | `String?` | Pre-login anonymous ID for event stitching |
| `payload.fcmToken` | `String?` | APNs / FCM push token |
| `payload.traits` | `PlayerTraits?` | Player profile attributes |
| `payload.unsetTraits` | `[String]?` | Trait keys to remove |
| `payload.timestamp` | `String?` | ISO-8601 — defaults to now |
| `completion` | `((SDKResponse) -> Void)?` | Invoked on main thread |

**PlayerTraits fields:**

| Field | Type | Description |
|---|---|---|
| `email` | `String?` | Player email |
| `phone` | `String?` | Phone in E.164 format |
| `firstName` | `String?` | First name |
| `lastName` | `String?` | Last name |
| `dateOfBirth` | `String?` | `YYYY-MM-DD` |
| `country` | `String?` | ISO 3166-1 alpha-2 (e.g. `MT`) |
| `currency` | `String?` | ISO currency code (e.g. `EUR`) |
| `language` | `String?` | Language code (e.g. `en`) |
| `kycStatus` | `String?` | `pending`, `approved`, `rejected` |
| `vipLevel` | `String?` | `bronze`, `silver`, `gold`, `platinum` |
| `accountStatus` | `String?` | `active`, `suspended`, `closed` |
| `registrationDate` | `String?` | ISO-8601 datetime |
| `brandId` | `String?` | Brand/operator identifier |
| `custom` | `[String: Any]` | Any additional key-value pairs |

---

### `SignalSDK.shared.clearIdentity()`

Clears the active `userId`. Call on logout.

---

### `SignalSDK.shared.sendEvent(_:properties:completion:)`

| Parameter | Type | Required | Description |
|---|---|---|---|
| `eventName` | `String` | Yes | Non-empty event name |
| `properties` | `[String: Any]` | No | Key-value event data |
| `completion` | `((SDKResponse) -> Void)?` | No | Invoked on main thread |

---

### `SDKResponse`

```swift
public struct SDKResponse {
    public let success: Bool
    public let accepted: Int?   // events accepted (track calls)
    public let rejected: Int?   // events rejected (track calls)
    public let error: String?   // error message if success = false
}
```

---

## Notes

- **`initSDK` must be called first** from `AppDelegate` or `@main` App struct — not from a `UIViewController`.
- **`setIdentity` must be called after `initSDK`** before any events can be tracked.
- **Events do not require login** — anonymous identity is sufficient.
- **`setIdentity` is additive** — only passed fields are updated.
- **The completion is always invoked on the main thread** — safe to update UI directly.
- **No external dependencies** — the SDK uses only Foundation and UIKit.
