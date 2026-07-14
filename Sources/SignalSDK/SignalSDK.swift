import Foundation
import UIKit
import UserNotifications

/// Signal iOS SDK — main entry point.
///
/// Typical usage:
/// ```swift
/// // AppDelegate.application(_:didFinishLaunchingWithOptions:)
/// SignalSDK.shared.initSDK(config: SignalConfig(clientId: "…", clientSecret: "…"))
/// SignalSDK.shared.handleAppLaunch(options: launchOptions)   // cold-start push detection
///
/// // After determining auth state (anonymous or logged-in)
/// SignalSDK.shared.setIdentity(IdentityPayload(userId: userId))
///
/// // After login
/// SignalSDK.shared.setIdentity(IdentityPayload(userId: realUserId))
///
/// // After logout — generate a new anonymous UUID, then re-identify
/// SignalSDK.shared.clearIdentity()
/// SignalSDK.shared.setIdentity(IdentityPayload(userId: UUID().uuidString))
/// ```
///
/// Push notification wiring (AppDelegate):
/// ```swift
/// func application(_ application: UIApplication,
///                  didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
///     SignalSDK.shared.registerDeviceToken(deviceToken)
/// }
///
/// // UNUserNotificationCenterDelegate:
/// func userNotificationCenter(_ center: UNUserNotificationCenter,
///                             willPresent notification: UNNotification,
///                             withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
///     SignalSDK.shared.handleForegroundNotification(notification, completionHandler: completionHandler)
/// }
///
/// func userNotificationCenter(_ center: UNUserNotificationCenter,
///                             didReceive response: UNNotificationResponse,
///                             withCompletionHandler completionHandler: @escaping () -> Void) {
///     SignalSDK.shared.handleNotificationResponse(response)
///     completionHandler()
/// }
/// ```
public final class SignalSDK {

    public static let shared = SignalSDK()

    private var state = SDKState()
    private let lock  = NSLock()

    private var eventService:    EventService?
    private var identityService: IdentityService?
    private var lifecycleService: LifecycleService?

    // Stores notification userInfo from cold-start launch until identity is available
    private var pendingColdStartNotification: [AnyHashable: Any]?

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale     = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        f.timeZone   = TimeZone(identifier: "UTC")
        return f
    }()

    private static let qaPrefix    = "QA_"
    private static let prodBaseUrl = "https://api.wynta.com/api/v1"
    private static let qaBaseUrl   = "https://qa-app.fozilpartners.com/api/v1"

    private init() {}

    // ── Init ──────────────────────────────────────────────────────────────────

    /// Initialize the SDK. Call once from `AppDelegate.application(_:didFinishLaunchingWithOptions:)`.
    /// Does not require an identity — call `setIdentity(_:completion:)` immediately after.
    ///
    /// Prefix `clientId` with `QA_` to route all traffic to the QA environment.
    /// The prefix is stripped before being sent in API headers.
    public func initSDK(config: SignalConfig) {
        precondition(!config.clientId.isEmpty,     "clientId must not be empty")
        precondition(!config.clientSecret.isEmpty, "clientSecret must not be empty")

        if config.debug { Logger.enable() }

        // Wire up API logging callback
        ApiLogger.callback = config.onApiLog

        // Strip QA_ prefix and resolve the correct base URL
        let isQa       = config.clientId.hasPrefix(Self.qaPrefix)
        let cleanId    = isQa ? String(config.clientId.dropFirst(Self.qaPrefix.count)) : config.clientId
        let baseUrl    = isQa ? Self.qaBaseUrl : Self.prodBaseUrl

        Logger.log("initSDK | env=\(isQa ? "QA" : "PROD") | baseUrl=\(baseUrl)")

        let deviceService = DeviceService()
        let esvc  = EventService(deviceService: deviceService)
        let isvc  = IdentityService()
        let lsvc  = LifecycleService(
            getState: { [weak self] in self?.getState() ?? SDKState() },
            emit:     { [weak self] eventName in self?.emitLifecycleEvent(eventName) }
        )

        eventService     = esvc
        identityService  = isvc
        lifecycleService = lsvc

        // Restore persisted APNs token so it's available before setIdentity is called
        let savedToken = Storage.shared.get(StorageKey.apnsToken)

        updateState { s in
            var s = s
            s.clientId       = cleanId
            s.clientSecret   = config.clientSecret
            s.baseUrl        = baseUrl
            s.userId         = nil
            s.fcmToken       = savedToken
            s.appOpenTracked = false
            s.initialized    = true
            return s
        }

        if savedToken != nil { Logger.log("APNs token restored from storage") }

        // Fresh session on every cold launch
        SessionService.shared.reset()
        _ = SessionService.shared.getSessionId()

        lsvc.start()

        Logger.log("SDK initialized | session=\(SessionService.shared.getSessionId()) | call setIdentity() next")
    }

    // ── Push Notifications ────────────────────────────────────────────────────

    /// Call from `AppDelegate.application(_:didFinishLaunchingWithOptions:)` to detect cold-start
    /// notification taps. The SDK stores the payload and fires `notification_opened` automatically
    /// after the first successful `setIdentity` call.
    public func handleAppLaunch(options: [UIApplication.LaunchOptionsKey: Any]?) {
        guard let userInfo = options?[.remoteNotification] as? [AnyHashable: Any] else { return }
        Logger.log("Cold-start notification detected — will track after setIdentity")
        pendingColdStartNotification = userInfo
    }

    /// Request notification authorization (alert, sound, badge).
    /// Call once during onboarding or first launch.
    public func requestNotificationPermission(completion: @escaping (Bool, Error?) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            Logger.log("Notification permission: \(granted ? "granted" : "denied")")
            DispatchQueue.main.async { completion(granted, error) }
        }
    }

    /// Call from `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
    /// Converts the raw token to a hex string, persists it to UserDefaults, and updates the
    /// backend via `setIdentity` if a user is already identified.
    public func registerDeviceToken(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Logger.log("APNs token registered: \(token)")
        Storage.shared.set(StorageKey.apnsToken, token)
        updateState { s in var s = s; s.fcmToken = token; return s }
        let current = getState()
        if current.initialized, let userId = current.userId, !userId.isEmpty {
            setIdentity(IdentityPayload(userId: userId, fcmToken: token))
        }
    }

    /// Call from `userNotificationCenter(_:willPresent:withCompletionHandler:)`.
    /// Ensures notifications are shown as banners with sound even when the app is in the foreground.
    public func handleForegroundNotification(
        _ notification: UNNotification,
        completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound, .badge])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
    }

    /// Call from `userNotificationCenter(_:didReceive:withCompletionHandler:)`.
    /// Extracts campaign data and fires `notification_opened` (banner tap) or
    /// `notification_clicked` (action button tap).
    public func handleNotificationResponse(_ response: UNNotificationResponse) {
        let userInfo  = response.notification.request.content.userInfo
        let isDefault = response.actionIdentifier == UNNotificationDefaultActionIdentifier
        let isDismiss = response.actionIdentifier == UNNotificationDismissActionIdentifier
        guard !isDismiss else { return }
        let actionId  = isDefault ? nil : response.actionIdentifier
        trackNotificationInteraction(userInfo: userInfo, actionId: actionId)
    }

    // ── Identity ──────────────────────────────────────────────────────────────

    /// Set or update the active identity. Pass the logged-in user ID or an anonymous UUID.
    ///
    /// On the **first call after `initSDK`** the SDK automatically fires:
    ///   `sdk_init` → `session_started` → `app_opened`
    ///
    /// Subsequent calls (e.g. login, APNs token refresh) only call the identify API.
    ///
    /// - Parameter completion: Optional result callback, invoked on the main thread.
    public func setIdentity(_ payload: IdentityPayload, completion: ((SDKResponse) -> Void)? = nil) {
        let current = getState()
        guard current.initialized else {
            completion?(SDKResponse(success: false, error: "SDK not initialized. Call initSDK() first."))
            return
        }

        let userId = payload.userId ?? current.userId
        guard let userId, !userId.isEmpty else {
            completion?(SDKResponse(success: false, error: "userId is required."))
            return
        }

        let fcmToken = payload.fcmToken ?? current.fcmToken

        // Flatten traits into a plain map so the backend receives snake_case keys
        var traitsMap: [String: Any] = [:]
        if let t = payload.traits {
            if let v = t.email            { traitsMap["email"]             = v }
            if let v = t.phone            { traitsMap["phone"]             = v }
            if let v = t.firstName        { traitsMap["first_name"]        = v }
            if let v = t.lastName         { traitsMap["last_name"]         = v }
            if let v = t.dateOfBirth      { traitsMap["date_of_birth"]     = v }
            if let v = t.country          { traitsMap["country"]           = v }
            if let v = t.currency         { traitsMap["currency"]          = v }
            if let v = t.language         { traitsMap["language"]          = v }
            if let v = t.kycStatus        { traitsMap["kyc_status"]        = v }
            if let v = t.vipLevel         { traitsMap["vip_level"]         = v }
            if let v = t.accountStatus    { traitsMap["account_status"]    = v }
            if let v = t.registrationDate { traitsMap["registration_date"] = v }
            if let v = t.brandId          { traitsMap["brand_id"]          = v }
            traitsMap.merge(t.custom) { _, new in new }
        }
        // Always merge fcm_token into traits so it reaches the backend
        if let token = fcmToken { traitsMap["fcm_token"] = token }

        // Persist APNs token so it survives app restarts
        if let token = fcmToken { Storage.shared.set(StorageKey.apnsToken, token) }

        // Update in-memory state before the network call
        updateState { s in var s = s; s.userId = userId; s.fcmToken = fcmToken; return s }

        let request = IdentifyRequest(
            user_id:      userId,
            anonymous_id: payload.anonymousId,
            traits:       traitsMap.isEmpty ? nil : traitsMap,
            unset_traits: payload.unsetTraits,
            timestamp:    payload.timestamp ?? Self.isoFormatter.string(from: Date())
        )

        Logger.log("setIdentity → user: \(userId)")

        let wasTracked   = current.appOpenTracked
        let clientId     = current.clientId!
        let clientSecret = current.clientSecret!
        let baseUrl      = current.baseUrl

        identityService?.identifyPlayer(request, clientId: clientId, clientSecret: clientSecret, baseUrl: baseUrl) { [weak self] result in
            guard let self else { return }
            if result.success && !wasTracked {
                self.updateState { s in var s = s; s.appOpenTracked = true; return s }
                // Auto-track init bundle — same order as Android + RN SDKs
                ["sdk_init", "session_started", "app_opened"].forEach { self.emitLifecycleEvent($0) }
                // Flush cold-start notification interaction now that identity is established
                if let pending = self.pendingColdStartNotification {
                    self.pendingColdStartNotification = nil
                    self.trackNotificationInteraction(userInfo: pending)
                }
            }
            DispatchQueue.main.async { completion?(result) }
        }
    }

    /// Clear the active identity (call on logout).
    /// Generate a new anonymous UUID and call `setIdentity(_:)` immediately after.
    public func clearIdentity() {
        updateState { s in var s = s; s.userId = nil; return s }
        Logger.log("Identity cleared")
    }

    // ── Events ────────────────────────────────────────────────────────────────

    /// Track a custom event.
    ///
    /// - Parameters:
    ///   - eventName:  Non-empty event name (e.g. `"deposit_success"`).
    ///   - properties: Arbitrary key-value properties. Supports nested dictionaries and arrays.
    ///                 Reserved keys (`user_id`, `session_id`, `event_id`, etc.) are silently removed.
    ///   - completion: Optional result callback, invoked on the main thread.
    public func sendEvent(
        _ eventName: String,
        properties: [String: Any] = [:],
        completion: ((SDKResponse) -> Void)? = nil
    ) {
        let current = getState()
        guard current.initialized else {
            completion?(SDKResponse(success: false, error: "SDK not initialized. Call initSDK() first."))
            return
        }
        guard let userId = current.userId, !userId.isEmpty else {
            completion?(SDKResponse(success: false, error: "No identity set. Call setIdentity() first."))
            return
        }
        precondition(!eventName.isEmpty, "eventName must not be empty")

        guard let event = eventService?.buildEvent(eventName: eventName, properties: properties, userId: userId) else { return }
        Logger.log("sendEvent: \(eventName) | event_id=\(event.event_id)")

        let clientId     = current.clientId!
        let clientSecret = current.clientSecret!
        let baseUrl      = current.baseUrl

        eventService?.trackEvent(event, clientId: clientId, clientSecret: clientSecret, baseUrl: baseUrl) { result in
            DispatchQueue.main.async { completion?(result) }
        }
    }

    // ── Internal ──────────────────────────────────────────────────────────────

    private func trackNotificationInteraction(userInfo: [AnyHashable: Any], actionId: String? = nil) {
        let campaignId = userInfo["campaign_id"] as? String
                      ?? userInfo["wynta_campaign_id"] as? String
        guard let campaignId else { return }

        let eventName = (actionId != nil) ? "notification_clicked" : "notification_opened"

        var props: [String: Any] = [
            "campaign_id":       campaignId,
            "notification_type": userInfo["notification_type"] as? String ?? "promotional",
            "channel":           userInfo["channel"] as? String ?? "push",
        ]
        if let v = userInfo["campaign_name"] as? String { props["campaign_name"] = v }
        if let v = userInfo["template_id"]   as? String { props["template_id"]   = v }
        if let v = userInfo["deep_link"]     as? String { props["deep_link"]     = v }
        if let aid = actionId                           { props["action_id"]     = aid }

        Logger.log("Push interaction: \(eventName) | campaign=\(campaignId)")
        sendEvent(eventName, properties: props)
    }

    private func emitLifecycleEvent(_ eventName: String) {
        let current = getState()
        guard current.initialized, let userId = current.userId, !userId.isEmpty else { return }
        guard let event = eventService?.buildEvent(eventName: eventName, properties: [:], userId: userId) else { return }
        Logger.log("Lifecycle event: \(eventName) | event_id=\(event.event_id)")
        let clientId     = current.clientId!
        let clientSecret = current.clientSecret!
        let baseUrl      = current.baseUrl
        eventService?.trackEvent(event, clientId: clientId, clientSecret: clientSecret, baseUrl: baseUrl) { _ in }
    }

    private func getState() -> SDKState {
        lock.lock(); defer { lock.unlock() }
        return state
    }

    private func updateState(_ update: (SDKState) -> SDKState) {
        lock.lock(); defer { lock.unlock() }
        state = update(state)
    }
}
