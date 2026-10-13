import Foundation

// Parsed from the APNs `userInfo` dictionary for campaign pushes that use one of the SDK-
// rendered templates. `template` selects which fields the NSE / Content Extension read —
// see docs/push-templates.md for the full contract.
internal struct PushNotificationPayload {
    let template: String
    let title: String
    let body: String
    let accentColorHex: String?
    let imageUrl: String?
    // The composer's "Add a rich image" — full-width image above the title/body on the
    // "standard" and "branded" templates only (hero_banner has its own imageUrl).
    let richImageUrl: String?
    // Overrides the title/body text color on all three templates — unlike accentColorHex/
    // imageUrl/richImageUrl, not scoped to a single template.
    let textColor: String?
    let notificationTapType: String?
    let notificationTapAction1: String?
    let notificationTapAction2: String?
    // Carried through unchanged so trackNotificationInteraction can still populate its
    // existing campaign fields when they're present alongside the new template fields.
    let campaignId: String?
    let campaignName: String?
    let notificationType: String?
    let channel: String?
    let templateId: String?
    let actionId: String?
    let deepLink: String?

    static func from(userInfo: [AnyHashable: Any]) -> PushNotificationPayload? {
        func string(_ key: String) -> String? {
            (userInfo[key] as? String)?.isEmpty == false ? (userInfo[key] as? String) : nil
        }

        // The composer sends the description text as "content", not "body" -- "body" is kept as
        // a fallback for any already-scheduled campaigns/older backend versions still using the
        // old key.
        guard let title = string("title"), let body = string("content") ?? string("body") else { return nil }

        return PushNotificationPayload(
            // Normalized so "Branded"/"HERO_BANNER"/etc. from the composer still match —
            // same case-sensitivity bug found and fixed on Android.
            template: (string("template") ?? "standard").lowercased(),
            title: title,
            body: body,
            // bg_color/banner_url are the current composer field names;
            // accentColorHex/imageUrl kept as fallbacks for the same reason.
            accentColorHex: string("bg_color") ?? string("accentColorHex"),
            imageUrl: string("banner_url") ?? string("imageUrl"),
            // image_url used to be the branded large icon beside the text; branded no longer
            // has one — the composer now sends the rich image as image_url.
            richImageUrl: string("image_url"),
            textColor: string("text_color"),
            // Lowercased to match the native Android SDK, where a "Dismiss"/"DEEPLINK" case
            // variance from the backend shouldn't produce two different values downstream.
            notificationTapType: string("notification_tap_type")?.lowercased(),
            notificationTapAction1: string("notification_tap_action_1"),
            notificationTapAction2: string("notification_tap_action_2"),
            campaignId: string("campaign_id") ?? string("wynta_campaign_id"),
            campaignName: string("campaign_name"),
            notificationType: string("notification_type"),
            channel: string("channel"),
            templateId: string("template_id"),
            actionId: string("action_id"),
            deepLink: string("deep_link")
        )
    }
}
