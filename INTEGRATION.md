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

### 1.1 Swift Package Manager (recommended)

In Xcode:

1. **File → Add Package Dependencies**
2. Enter the repository URL:
   ```
   https://github.com/signal-sdk/ios-sdk
   ```
3. Select **Up to Next Major Version** → `1.0.0`
4. Add `SignalSDK` to your app target

Or add it to your `Package.swift` (for framework targets):

```swift
dependencies: [
    .package(url: "https://github.com/signal-sdk/ios-sdk", from: "1.0.0")
],
targets: [
    .target(name: "YourApp", dependencies: ["SignalSDK"])
]
```

### 1.2 CocoaPods

Add to your `Podfile`:

```ruby
pod 'SignalSDK', '~> 1.0'
```

Then run:

```bash
pod install
```

Open the generated `.xcworkspace` (not `.xcodeproj`) going forward.

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
