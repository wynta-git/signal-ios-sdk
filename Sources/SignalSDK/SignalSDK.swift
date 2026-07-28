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
///     SignalSDK.shared.registerDeviceToken(deviceToken)   // raw APNs token (fallback only)
/// }
///
/// // If the app also integrates Firebase Messaging, register the real FCM token instead —
/// // this is what the backend needs to actually deliver pushes via FCM:
/// // MessagingDelegate:
/// func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
///     guard let fcmToken else { return }
///     SignalSDK.shared.registerFcmToken(fcmToken)
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
    private var notificationInboxService: NotificationInboxService?

    // Stores notification userInfo from cold-start launch until identity is available
    private var pendingColdStartNotification: [AnyHashable: Any]?

    // Strong reference to the currently-shown in-app popup — nothing else retains it.
    private var currentPopup: InAppPopupWindow?

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
        let nsvc  = NotificationInboxService()
        let lsvc  = LifecycleService(
            getState:   { [weak self] in self?.getState() ?? SDKState() },
            emit:       { [weak self] eventName in self?.emitLifecycleEvent(eventName) },
            checkInbox: { [weak self] in self?.checkInbox() }
        )

        eventService     = esvc
        identityService  = isvc
        notificationInboxService = nsvc
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
    ///
    /// - Note: This is the raw APNs device token, not an FCM registration token. Push delivery
    ///   goes through FCM, which requires the actual FCM token — if the app also integrates
    ///   Firebase Messaging, call `registerFcmToken(_:)` from
    ///   `MessagingDelegate.messaging(_:didReceiveRegistrationToken:)` instead/as well, since
    ///   that's the value the backend actually needs to deliver pushes.
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

    /// Call from `MessagingDelegate.messaging(_:didReceiveRegistrationToken:)` (Firebase
    /// Messaging) with the actual FCM registration token. This is what the backend needs to
    /// deliver pushes via FCM — the raw APNs token from `registerDeviceToken(_:)` is not a
    /// valid substitute. Persists it and updates the backend via `setIdentity` if a user is
    /// already identified.
    public func registerFcmToken(_ fcmToken: String) {
        Logger.log("FCM token registered: \(fcmToken)")
        Storage.shared.set(StorageKey.apnsToken, fcmToken)
        updateState { s in var s = s; s.fcmToken = fcmToken; return s }
        let current = getState()
        if current.initialized, let userId = current.userId, !userId.isEmpty {
            setIdentity(IdentityPayload(userId: userId, fcmToken: fcmToken))
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

            // Inbox is per-user — refetch whenever the identified user actually changes. This
            // covers both the cold-start case (current.userId was nil) and a later login that
            // switches from an anonymous id to a real user id. app_foreground never fires on a
            // fresh launch, so the cold-start case isn't otherwise covered.
            if result.success && userId != current.userId {
                self.checkInbox()
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

        // on_custom_event evaluation — purely local, no network dependency, so it runs
        // regardless of whether the /events/track call below succeeds.
        if !current.isInAppPopupVisible {
            if let notification = TriggerEngine.findEligibleNotification(
                notifications: current.notificationCache,
                event: .customEvent(eventName: eventName),
                handledIds: current.handledInAppNotificationIds
            ) {
                displayNotification(notification)
            }
        }

        guard let event = eventService?.buildEvent(eventName: eventName, properties: properties, userId: userId) else { return }
        Logger.log("sendEvent: \(eventName) | event_id=\(event.event_id)")

        let clientId     = current.clientId!
        let clientSecret = current.clientSecret!
        let baseUrl      = current.baseUrl

        eventService?.trackEvent(event, clientId: clientId, clientSecret: clientSecret, baseUrl: baseUrl) { result in
            DispatchQueue.main.async { completion?(result) }
        }
    }

    // ── Screens & In-App Notifications ───────────────────────────────────────

    /// Call this whenever a screen becomes visible to the user. The SDK stores the current
    /// screen, fires the `screen_viewed` analytics event, and evaluates any cached in-app
    /// notifications targeting this screen — all without making a network request from this
    /// call itself (the inbox is cached from the last `checkInbox()` fetch).
    public func trackScreen(_ screenName: String) {
        guard !screenName.isEmpty else {
            Logger.log("trackScreen: screenName must not be empty")
            return
        }
        let current = getState()
        guard current.initialized else {
            Logger.log("trackScreen skipped — SDK not initialized")
            return
        }

        let referrer = current.currentScreen
        updateState { s in
            var s = s
            s.previousScreen = current.currentScreen
            s.currentScreen  = screenName
            return s
        }

        if let userId = current.userId, !userId.isEmpty, current.clientId != nil, current.clientSecret != nil {
            var props: [String: Any] = ["screen_name": screenName]
            if let referrer { props["referrer"] = referrer }
            trackDirectEvent("screen_viewed", properties: props, userId: userId)
        }

        guard !current.isInAppPopupVisible else { return } // don't stack a popup on rapid navigation

        if let notification = TriggerEngine.findEligibleNotification(
            notifications: current.notificationCache,
            event: .screenLoad(screenName: screenName),
            handledIds: current.handledInAppNotificationIds
        ) {
            displayNotification(notification)
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
        trackDirectEvent(eventName, properties: [:], userId: userId)
    }

    // Sends an event straight through EventService, bypassing sendEvent()'s on_custom_event
    // trigger check — used for interaction/lifecycle events that must not themselves be able
    // to re-trigger an in-app popup.
    private func trackDirectEvent(_ eventName: String, properties: [String: Any], userId: String) {
        let current = getState()
        guard let event = eventService?.buildEvent(eventName: eventName, properties: properties, userId: userId) else { return }
        Logger.log("trackDirectEvent: \(eventName) | event_id=\(event.event_id)")
        let clientId     = current.clientId!
        let clientSecret = current.clientSecret!
        let baseUrl      = current.baseUrl
        eventService?.trackEvent(event, clientId: clientId, clientSecret: clientSecret, baseUrl: baseUrl) { _ in }
    }

    /// Fetches the notification inbox, caches it for `trackScreen`/`sendEvent` trigger checks,
    /// and — unless a popup is already showing — evaluates the on_session_start trigger and
    /// displays the first eligible match. Called after the first identity is set, whenever the
    /// identified user changes, and on every app_foreground.
    private func checkInbox() {
        let current = getState()
        guard current.initialized,
              let userId = current.userId, !userId.isEmpty,
              let clientId = current.clientId,
              let clientSecret = current.clientSecret else {
            Logger.log("checkInbox skipped — no active identity")
            return
        }

        notificationInboxService?.fetchInbox(
            userId: userId, clientId: clientId, clientSecret: clientSecret, baseUrl: current.baseUrl
        ) { [weak self] inbox, error in
            guard let self else { return }
            guard let inbox else {
                Logger.error("checkInbox failed: \(error ?? "unknown error")")
                return
            }
            Logger.log("checkInbox → \(inbox.notifications.count) notification(s)")
            self.updateState { s in var s = s; s.notificationCache = inbox.notifications; return s }

            let latest = self.getState()
            guard !latest.isInAppPopupVisible else { return } // don't stack a popup on top of one already shown

            if let notification = TriggerEngine.findEligibleNotification(
                notifications: inbox.notifications,
                event: .sessionStart,
                handledIds: latest.handledInAppNotificationIds
            ) {
                self.displayNotification(notification)
            }
        }
    }

    // Shared by the session-start path (checkInbox) and the screen-load/custom-event paths
    // (trackScreen, sendEvent) — marks the notification handled, guards further popups until
    // this one is dismissed, and hands off to the native renderer.
    private func displayNotification(_ notification: InboxNotification) {
        updateState { s in
            var s = s
            s.handledInAppNotificationIds.append(notification.notification_id)
            s.isInAppPopupVisible = true
            return s
        }

        guard let imageUrl = notification.media?.image_url, !imageUrl.isEmpty else {
            Logger.log("displayNotification: no image_url — dismissing \(notification.notification_id)")
            updateState { s in var s = s; s.isInAppPopupVisible = false; return s }
            return
        }

        guard currentPopup == nil else {
            Logger.log("displayNotification: a popup is already showing — skipped \(notification.notification_id)")
            return
        }

        let cta = notification.cta?.first
        Logger.log("displayNotification: showing \(notification.notification_id)")

        let popup = InAppPopupWindow()
        currentPopup = popup
        popup.present(
            imageURL: imageUrl,
            ctaAction: cta?.action ?? "dismiss",
            ctaValue: cta?.value,
            ctaLabel: cta?.label
        ) { [weak self] interactionType, ctaLabel in
            self?.onInAppInteraction(
                type: interactionType,
                notificationId: notification.notification_id,
                campaignId: notification.campaign_id,
                ctaLabel: ctaLabel
            )
        }
    }

    // Reported back by InAppPopupWindow for shown/clicked/dismissed. `shown` also marks the
    // notification read; `clicked`/`dismissed` clear the popup-visible guard.
    private func onInAppInteraction(type: String, notificationId: String, campaignId: String, ctaLabel: String?) {
        let current = getState()
        guard let userId = current.userId, !userId.isEmpty,
              let clientId = current.clientId,
              let clientSecret = current.clientSecret else { return }

        Logger.log("onInAppInteraction: \(type) | notification=\(notificationId)")

        switch type {
        case "shown":
            trackDirectEvent(
                "in_app_notification_viewed",
                properties: ["notification_id": notificationId, "campaign_id": campaignId],
                userId: userId
            )
            notificationInboxService?.markNotificationsRead(
                [notificationId], userId: userId, clientId: clientId, clientSecret: clientSecret, baseUrl: current.baseUrl
            ) { error in
                if let error {
                    Logger.error("markNotificationsRead failed: \(error)")
                }
            }
        case "clicked":
            var props: [String: Any] = ["notification_id": notificationId, "campaign_id": campaignId]
            if let ctaLabel { props["cta_label"] = ctaLabel }
            trackDirectEvent("in_app_notification_clicked", properties: props, userId: userId)
            updateState { s in var s = s; s.isInAppPopupVisible = false; return s }
            currentPopup = nil
        case "dismissed":
            trackDirectEvent(
                "in_app_notification_dismissed",
                properties: ["notification_id": notificationId, "campaign_id": campaignId],
                userId: userId
            )
            updateState { s in var s = s; s.isInAppPopupVisible = false; return s }
            currentPopup = nil
        default:
            break
        }
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
