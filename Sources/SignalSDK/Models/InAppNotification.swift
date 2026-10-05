internal struct NotificationCta {
    let role: String?            // "primary" | "secondary"
    let label: String?
    let action: String           // "deep_link" | "external_url" | "dismiss"
    let value: String?
    let cta_background_color: String?
}

internal struct NotificationMedia {
    let image_url: String?
    let background_color: String?
    let background_opacity: String?  // "opaque" | "translucent" | "transparent" — not yet applied
}

internal struct InboxNotification {
    let notification_id: String
    let campaign_id: String
    let variant_id: String?
    // "full_screen" | "pop_ups" | "bubble" — nil/unrecognized falls back to the original
    // fixed image-card layout, so already-scheduled campaigns without this field keep
    // rendering exactly as before.
    let template_type: String?
    // "native" | "html" — only "native" is rendered today; "html" notifications are
    // currently dropped since there's no WebView-based renderer yet.
    let render_engine: String?
    let title: String?
    let body: String?
    let media: NotificationMedia?
    // Rendered in list order, independent of count — each entry is its own button.
    let cta: [NotificationCta]?
    // Any value other than "never" shows the close button (default "always").
    let close_button_visibility: String?
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
