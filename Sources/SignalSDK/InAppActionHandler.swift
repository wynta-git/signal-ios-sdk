/// Register via `SignalSDK.shared.setInAppActionListener(_:)` to receive in-app message CTA
/// taps whose `action` is `"deep_link"`. The SDK has no knowledge of the host app's internal
/// navigation, so it hands the opaque `value` (e.g. "wallet", "deposit") back to the app to
/// route however it sees fit — the same hand-off push notifications already do via `userInfo`
/// for `notification_tap_action_1`, just delivered as a direct callback here since an in-app
/// message only ever shows while the app is already running in the foreground.
///
/// `"external_url"` CTAs are opened directly by the SDK's own in-app browser and never reach
/// this handler. `"dismiss"` CTAs just close the message — nothing is delivered here either.
public typealias InAppActionHandler = (
    _ action: String,
    _ value: String?,
    _ ctaLabel: String?,
    _ notificationId: String,
    _ campaignId: String
) -> Void
