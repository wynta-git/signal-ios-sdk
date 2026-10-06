# Changelog

All notable changes to the Signal iOS SDK are documented here.

## 1.7.12

- `bubble`: fixed sitting flush against the home indicator safe area instead of floating above
  it — position now accounts for `window.safeAreaInsets.bottom`.
- `bubble`: base floating margin increased from 24pt to 28pt.
- `bubble`: image height increased from 100pt to 120pt (was cropping too tight).

## 1.7.11

- `full_screen`: when there's no image, the title/body/CTA block is now anchored near the top
  (below the close button) instead of being vertically centered, which previously left a large
  empty gap above the title.
- `full_screen`: image height reduced from 45% to 35% of screen height.
- Widened title→body and body→button spacing across `full_screen` and `pop_ups`/`bubble`.
- Body text size increased from 14pt to 15pt.
- A CTA whose label is empty (not nil) is no longer rendered, matching the existing nil-label
  behavior — applies to both `showTestInAppMessage` and the shared renderer.

## 1.7.10

- `showTestInAppMessage` now supports a second (secondary) CTA button — disabled by default,
  pass `secondCtaLabel` (plus `secondCtaAction`/`secondCtaValue`/`secondCtaBackgroundColor`) to
  enable it. Matches the renderer's existing generic multi-CTA support.

## 1.7.9

- Added in-app message templates: `template_type` now selects `full_screen` (covers the whole
  screen), `pop_ups` (centered card over a dim scrim), or `bubble` (small card anchored to the
  bottom, no scrim) — each showing image/title/body/CTA row only when present in the payload.
  Any other/missing `template_type` falls back to the original fixed image-card layout, so
  already-scheduled campaigns keep rendering unchanged.
- Added `InAppActionHandler` / `SignalSDK.shared.setInAppActionListener(_:)` — the host app
  registers this to receive in-app CTA taps whose action is `deep_link`, since the SDK has no
  knowledge of the app's internal navigation. `external_url` CTAs continue to open in the SDK's
  own in-app browser; `dismiss` just closes.
- Added `SignalSDK.shared.showTestInAppMessage(...)` — a temporary testing aid that renders a
  test in-app message directly, bypassing inbox fetch/trigger matching, for verifying the new
  templates ahead of backend support for the new payload fields.

## 1.7.8

- Removed the dark gradient scrim behind `hero_banner`'s overlaid title/body text in the
  expanded Content Extension UI — text now sits directly on the image with no background
  treatment.

## 1.7.7

- `notification_tap_type` is now lowercased at parse time and wherever it's read for analytics
  (`SignalSDK.trackNotificationInteraction`), matching the native Android SDK's normalization.
  Previously a backend-sent `"Deeplink"`/`"DEEPLINK"` would pass through with its original
  casing on iOS while Android always normalized to `"deeplink"`.

## 1.7.6

- Added `text_color` to the push template payload contract: overrides the title/body text
  color in the expanded Content Extension UI on all three templates (`standard`/`branded`/
  `hero_banner`), unlike `bg_color`/`image_url`/`banner_url` which are each scoped to one
  template. Ignored if invalid or absent, in which case each template's default color applies.

## 1.7.5

- Custom push notification templates (`standard`/`branded`/`hero_banner`) now read the
  campaign composer's current field names: body text as `content` (was `body`), Branded's
  accent color as `bg_color` (was `accentColorHex`), Branded's icon as `image_url` (was
  `largeIconUrl`), and Hero Banner's image as `banner_url` (was `imageUrl`). The old field
  names are still accepted as a fallback for already-scheduled campaigns.

## 1.3.0

- Fixed the in-app popup's close button not registering taps on part of
  its visible area. It was a subview of the image card, positioned half
  above the card's own bounds — UIKit's default hitTest rejects touches
  outside a view's own bounds before checking subviews, so only the
  bottom half of the button actually worked. Now a sibling of the card
  with its own entrance animation, matching the Android port.

## 1.2.0

- Added in-app notification support: inbox fetch/cache, a trigger engine
  (`on_session_start`, `on_screen_load`, `on_custom_event`), and native
  popup + web-view overlay rendering (`InAppPopupWindow`, `InAppWebViewWindow`).
- Added `SignalSDK.shared.trackScreen(_:)` for screen-load triggers.
- Version bumped to match the Android SDK (`1.2.0`) for cross-platform parity.

## 1.0.0

- Initial public release: identity management, custom event tracking, and
  automatic lifecycle events (foreground, background, session).
