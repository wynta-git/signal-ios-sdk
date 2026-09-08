import Foundation
import UserNotifications

/// Reusable logic for a host app's own `UNNotificationServiceExtension` target — SwiftPM code
/// cannot itself *be* an extension, so this only does the mutation; the host app's extension
/// target is a thin shell that calls `populate(request:bestAttemptContent:contentHandler:)`
/// from `didReceive(_:withContentHandler:)`.
///
/// Downloads `imageUrl` for `hero_banner` pushes and attaches it via `UNNotificationAttachment`
/// so both the default OS banner and the Content Extension (`PushNotificationContentViewController`)
/// can show it — the Content Extension reuses this attachment rather than downloading again.
///
/// Example host-app extension:
/// ```swift
/// import UserNotifications
/// import SignalSDK
///
/// class NotificationService: UNNotificationServiceExtension {
///     var contentHandler: ((UNNotificationContent) -> Void)?
///     var bestAttemptContent: UNMutableNotificationContent?
///
///     override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
///         self.contentHandler = contentHandler
///         bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
///         guard let bestAttemptContent else { contentHandler(request.content); return }
///         PushNotificationExtensionHelper.populate(request: request, bestAttemptContent: bestAttemptContent, contentHandler: contentHandler)
///     }
///
///     override func serviceExtensionTimeWillExpire() {
///         if let contentHandler, let bestAttemptContent { contentHandler(bestAttemptContent) }
///     }
/// }
/// ```
public final class PushNotificationExtensionHelper {

    private static let imageTimeout: TimeInterval = 10
    // Guard against a misconfigured/huge image stalling the extension's ~30s time budget.
    private static let maxImageBytes = 5 * 1024 * 1024

    public static func populate(
        request: UNNotificationRequest,
        bestAttemptContent: UNMutableNotificationContent,
        contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        // Route to the Content Extension regardless of template — its own didReceive(_:) falls
        // back to a plain title/body layout for "standard", so this is safe either way.
        bestAttemptContent.categoryIdentifier = SignalSDK.pushCategoryIdentifier

        guard
            let payload = PushNotificationPayload.from(userInfo: bestAttemptContent.userInfo),
            payload.template == "hero_banner",
            let imageUrl = payload.imageUrl,
            let url = URL(string: imageUrl)
        else {
            contentHandler(bestAttemptContent)
            return
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = imageTimeout
        let session = URLSession(configuration: config)

        let task = session.downloadTask(with: url) { location, response, error in
            defer { contentHandler(bestAttemptContent) } // always call through, even on failure

            guard error == nil, let location else { return }
            if let httpResponse = response as? HTTPURLResponse {
                guard httpResponse.statusCode == 200, httpResponse.expectedContentLength <= Int64(maxImageBytes) else { return }
            }

            // downloadTask hands us a temp file that's deleted as soon as this closure returns —
            // copy it to our own temp location (with the right extension) before attaching.
            let fileExtension = (url.pathExtension.isEmpty ? "jpg" : url.pathExtension)
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(fileExtension)

            do {
                try FileManager.default.moveItem(at: location, to: destination)
                let attachment = try UNNotificationAttachment(identifier: "hero_image", url: destination, options: nil)
                bestAttemptContent.attachments = [attachment]
            } catch {
                Logger.error("PushNotificationExtensionHelper: attachment failed: \(error)")
            }
        }
        task.resume()
    }
}
