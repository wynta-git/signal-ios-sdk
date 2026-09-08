import UIKit
import UserNotifications
import UserNotificationsUI

/// Reusable expanded-notification UI for a host app's own Notification Content Extension
/// target (`UNNotificationContentExtension`) — SwiftPM code cannot itself be an extension, so
/// the host app's extension target references this class directly as its
/// `NSExtensionPrincipalClass` (e.g. `SignalSDK.PushNotificationContentViewController`), with
/// the extension's Info.plist `UNNotificationExtensionCategory` set to
/// `SignalSDK.pushCategoryIdentifier` so iOS routes matching pushes here on expand.
///
/// This is a functional first pass, not a pixel-match of the composer's template previews:
/// `branded` gets an accent-colored header, `hero_banner` gets a full-bleed image (reusing the
/// attachment `PushNotificationExtensionHelper` already downloaded — no second fetch),
/// `standard` gets the same plain title/body layout as the OS default. The collapsed banner is
/// always OS-standard regardless of what's drawn here — only the expanded/long-press view uses
/// this UI, which is a platform constraint, not a bug.
open class PushNotificationContentViewController: UIViewController, UNNotificationContentExtension {

    private let headerView = UIView()
    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private var imageHeightConstraint: NSLayoutConstraint!

    override open func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        buildLayout()
    }

    // MARK: - UNNotificationContentExtension

    open func didReceive(_ notification: UNNotification) {
        let payload = PushNotificationPayload.from(userInfo: notification.request.content.userInfo)

        titleLabel.text = payload?.title ?? notification.request.content.title
        bodyLabel.text  = payload?.body  ?? notification.request.content.body

        headerView.backgroundColor = .clear
        imageView.image = nil
        imageHeightConstraint.constant = 0

        switch payload?.template {
        case "branded":
            if let hex = payload?.accentColorHex, let color = UIColor(hex: hex) {
                headerView.backgroundColor = color
            }
        case "hero_banner":
            if let attachment = notification.request.content.attachments.first,
               attachment.url.startAccessingSecurityScopedResource() {
                defer { attachment.url.stopAccessingSecurityScopedResource() }
                if let data = try? Data(contentsOf: attachment.url) {
                    imageView.image = UIImage(data: data)
                    imageHeightConstraint.constant = 200
                }
            }
        default:
            break // "standard" — plain title/body layout below
        }
    }

    // MARK: - Layout

    private func buildLayout() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true

        titleLabel.font = .boldSystemFont(ofSize: 15)
        titleLabel.numberOfLines = 2

        bodyLabel.font = .systemFont(ofSize: 13)
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 4

        let textStack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false

        headerView.addSubview(imageView)
        view.addSubview(headerView)
        view.addSubview(textStack)

        imageHeightConstraint = imageView.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            imageView.topAnchor.constraint(equalTo: headerView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
            imageHeightConstraint,

            textStack.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 12),
            textStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            textStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            textStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
        ])
    }
}

private extension UIColor {
    convenience init?(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let rgb = UInt32(cleaned, radix: 16) else { return nil }
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
