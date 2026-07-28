# Changelog

All notable changes to the Signal iOS SDK are documented here.

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
