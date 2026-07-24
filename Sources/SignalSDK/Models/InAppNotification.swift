internal struct NotificationCta {
    let role: String?
    let label: String?
    let action: String
    let value: String?
}

internal struct NotificationMedia {
    let image_url: String?
}

internal struct InboxNotification {
    let notification_id: String
    let campaign_id: String
    let media: NotificationMedia?
    let cta: [NotificationCta]?
    let expires_at: String?
    // "on_session_start" | "on_screen_load" | "on_custom_event"
    let trigger_type: String?
    let target_screens: [String]?
    let target_events: [String]?
}

internal struct InboxResponse {
    let notifications: [InboxNotification]
    let next_cursor: String?
    let unread_count: Int
}
