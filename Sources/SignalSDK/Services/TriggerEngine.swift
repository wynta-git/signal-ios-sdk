import Foundation

internal enum TriggerEvent {
    case sessionStart
    case screenLoad(screenName: String)
    case customEvent(eventName: String)
}

/// One evaluator per trigger_type — adding a new trigger type means adding one branch
/// here, no changes needed at any call site. Mirrors the RN/Android SDKs' TriggerEngine.
internal enum TriggerEngine {

    private static let timestampFormatters: [DateFormatter] = {
        let patterns = [
            "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
        ]
        return patterns.map { pattern in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = pattern
            f.timeZone = TimeZone(identifier: "UTC")
            return f
        }
    }()

    static func findEligibleNotification(
        notifications: [InboxNotification],
        event: TriggerEvent,
        handledIds: [String]
    ) -> InboxNotification? {
        let match = notifications.first { notification in
            !handledIds.contains(notification.notification_id) &&
                !isExpired(notification.expires_at) &&
                !(notification.media?.image_url ?? "").isEmpty &&
                matchesTrigger(notification, event)
        }
        Logger.log("TriggerEngine.findEligibleNotification(\(event)) → \(match?.notification_id ?? "none")")
        return match
    }

    private static func isExpired(_ expiresAt: String?) -> Bool {
        guard let expiresAt, !expiresAt.isEmpty else { return false }
        guard let date = parseTimestamp(expiresAt) else { return false }
        return date < Date()
    }

    // Accepts a few ISO-8601 variants since backend timestamps may vary in precision/offset.
    private static func parseTimestamp(_ value: String) -> Date? {
        for formatter in timestampFormatters {
            if let date = formatter.date(from: value) { return date }
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: value)
    }

    private static func matchesTrigger(_ notification: InboxNotification, _ event: TriggerEvent) -> Bool {
        switch notification.trigger_type {
        case "on_session_start":
            if case .sessionStart = event { return true }
            return false
        case "on_screen_load":
            if case .screenLoad(let screenName) = event {
                return notification.target_screens?.contains(screenName) ?? false
            }
            return false
        case "on_custom_event":
            if case .customEvent(let eventName) = event {
                return notification.target_events?.contains(eventName) ?? false
            }
            return false
        default:
            return false
        }
    }
}
