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
        let normalized = normalizeTimestamp(value)
        for formatter in timestampFormatters {
            if let date = formatter.date(from: normalized) { return date }
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: normalized) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: normalized)
    }

    // Backend timestamps are always UTC but sometimes omit the trailing 'Z'/offset
    // designator entirely, and may carry more than millisecond (e.g. 6-digit
    // microsecond) fractional-second precision that these formatters' 3-digit
    // fractional-second matching can't handle — either of which makes every
    // formatter above fail to parse, silently falling back to "never expired".
    // Normalize first: pad or truncate the fractional part to exactly 3 digits,
    // and append 'Z' only when no designator is present at all (an existing
    // numeric offset is left as-is for ISO8601DateFormatter to handle). Mirrors
    // the RN/Android SDKs' TriggerEngine fix for the same root cause.
    private static func normalizeTimestamp(_ value: String) -> String {
        var result = value
        if let fractionRange = result.range(of: "\\.[0-9]+", options: .regularExpression) {
            let digits = result[fractionRange].dropFirst() // strip the leading '.'
            let millis = String((digits + "000").prefix(3))
            result.replaceSubrange(fractionRange, with: ".\(millis)")
        }
        let hasDesignator = result.range(of: "Z$|[+-][0-9]{2}:?[0-9]{2}$", options: .regularExpression) != nil
        if !hasDesignator {
            result += "Z"
        }
        return result
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
