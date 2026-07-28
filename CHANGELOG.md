# Changelog

All notable changes to the Signal iOS SDK are documented here.

## 1.2.0

- Added in-app notification support: inbox fetch/cache, a trigger engine
  (`on_session_start`, `on_screen_load`, `on_custom_event`), and native
  popup + web-view overlay rendering (`InAppPopupWindow`, `InAppWebViewWindow`).
- Added `SignalSDK.shared.trackScreen(_:)` for screen-load triggers.
- Version bumped to match the Android SDK (`1.2.0`) for cross-platform parity.

## 1.0.0

- Initial public release: identity management, custom event tracking, and
  automatic lifecycle events (foreground, background, session).
