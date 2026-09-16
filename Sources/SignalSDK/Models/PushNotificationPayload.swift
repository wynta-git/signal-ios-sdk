import Foundation

// Parsed from the APNs `userInfo` dictionary for campaign pushes that use one of the SDK-
// rendered templates. `template` selects which fields the NSE / Content Extension read —
// see docs/push-templates.md for the full contract.
internal struct PushNotificationPayload {
    let template: String
    let title: String
    let body: String
    let accentColorHex: String?
    let largeIconUrl: String?
    let imageUrl: String?
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

        guard let title = string("title"), let body = string("body") else { return nil }

        return PushNotificationPayload(
            template: string("template") ?? "standard",
            title: title,
            body: body,
            accentColorHex: string("accentColorHex"),
            largeIconUrl: string("largeIconUrl"),
            imageUrl: string("imageUrl"),
            notificationTapType: string("notification_tap_type"),
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
