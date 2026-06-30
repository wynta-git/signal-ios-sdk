import Foundation
import UIKit

/// Signal iOS SDK — main entry point.
///
/// Typical usage:
/// ```swift
/// // AppDelegate.application(_:didFinishLaunchingWithOptions:)
/// SignalSDK.shared.initSDK(config: SignalConfig(clientId: "…", clientSecret: "…"))
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
public final class SignalSDK {

    public static let shared = SignalSDK()

    private var state = SDKState()
    private let lock  = NSLock()

    private var eventService:    EventService?
    private var identityService: IdentityService?
    private var lifecycleService: LifecycleService?

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

        updateState { s in
            var s = s
            s.clientId       = cleanId
            s.clientSecret   = config.clientSecret
            s.baseUrl        = baseUrl
            s.userId         = nil
            s.appOpenTracked = false
            s.initialized    = true
            return s
        }

        // Fresh session on every cold launch
        SessionService.shared.reset()
        _ = SessionService.shared.getSessionId()

        lsvc.start()

        Logger.log("SDK initialized | session=\(SessionService.shared.getSessionId()) | call setIdentity() next")
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
