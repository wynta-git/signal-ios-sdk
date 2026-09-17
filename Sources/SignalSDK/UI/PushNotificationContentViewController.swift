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
/// Mirrors the composer's three templates, matching the Android SDK's final rendering:
///   - `standard`: plain title/body, no color, no image.
///   - `branded`: the whole card is filled with `accentColorHex`, rounded corners, with an
///     optional small `largeIconUrl` icon at the trailing edge.
///   - `hero_banner`: the image fills the card edge-to-edge at its own aspect ratio (no fixed
///     height, so it isn't cropped), with title/body overlaid in white on a bottom gradient
///     scrim so text stays legible over any photo.
/// The collapsed banner is always OS-standard regardless of what's drawn here — only the
/// expanded/long-press view uses this UI, a platform constraint, not a bug.
open class PushNotificationContentViewController: UIViewController, UNNotificationContentExtension {

    // Matches the Android SDK's rounded-branded-card radius.
    private static let cardCornerRadius: CGFloat = 12
    // Matches the Android SDK's hero_banner scrim height and hero-image height clamp.
    private static let scrimHeight: CGFloat = 96
    private static let minHeroHeight: CGFloat = 120
    private static let maxHeroHeight: CGFloat = 220
    private static let largeIconSize: CGFloat = 44

    private let imageView = UIImageView()
    private let scrimView = UIView()
    private let scrimLayer = CAGradientLayer()
    private let largeIconView = UIImageView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()

    private var imageHeightConstraint: NSLayoutConstraint!
    private var textStackNormalConstraints: [NSLayoutConstraint] = []
    private var textStackOverlayConstraints: [NSLayoutConstraint] = []

    override open func viewDidLoad() {
        super.viewDidLoad()
        view.layer.cornerRadius = Self.cardCornerRadius
        view.clipsToBounds = true
        buildLayout()
    }

    override open func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrimLayer.frame = scrimView.bounds
    }

    // MARK: - UNNotificationContentExtension

    open func didReceive(_ notification: UNNotification) {
        let payload = PushNotificationPayload.from(userInfo: notification.request.content.userInfo)
        let template = payload?.template ?? "standard"

        titleLabel.text = payload?.title ?? notification.request.content.title
        bodyLabel.text  = payload?.body  ?? notification.request.content.body

        // Reset — didReceive can be called more than once for the same extension instance.
        view.backgroundColor = .clear
        imageView.image = nil
        largeIconView.image = nil
        largeIconView.isHidden = true
        scrimView.isHidden = true
        imageHeightConstraint.constant = 0
        titleLabel.textColor = .label
        bodyLabel.textColor = .secondaryLabel
        NSLayoutConstraint.deactivate(textStackOverlayConstraints)
        NSLayoutConstraint.activate(textStackNormalConstraints)

        switch template {
        case "branded":
            // Whole-card fill, not just a header strip — matches the composer mockup and the
            // Android SDK's rounded-branded-card fix (a colored header alone read as broken).
            if let hex = payload?.accentColorHex, let color = UIColor(hex: hex) {
                view.backgroundColor = color
            }
            if let icon = attachedImage(in: notification, identifier: "large_icon") {
                largeIconView.image = icon
                largeIconView.isHidden = false
            }

        case "hero_banner":
            guard let image = attachedImage(in: notification, identifier: "hero_image") else {
                break // silent fallback to plain layout, per spec — no image, nothing to show
            }
            imageView.image = image
            scrimView.isHidden = false

            // Sized to the image's own aspect ratio (clamped) instead of a fixed height, so a
            // wide banner doesn't get center-cropped — same fix as the Android SDK's hero_banner
            // height handling. iOS can measure the real card width directly, unlike RemoteViews.
            let cardWidth = view.bounds.width > 0 ? view.bounds.width : 320
            let aspectHeight = image.size.height > 0 ? cardWidth * (image.size.height / image.size.width) : Self.minHeroHeight
            imageHeightConstraint.constant = min(max(aspectHeight, Self.minHeroHeight), Self.maxHeroHeight)

            titleLabel.textColor = .white
            bodyLabel.textColor = UIColor.white.withAlphaComponent(0.9)
            NSLayoutConstraint.deactivate(textStackNormalConstraints)
            NSLayoutConstraint.activate(textStackOverlayConstraints)

        default:
            break // "standard" — plain title/body layout, nothing further to configure
        }

        preferredContentSize = CGSize(
            width: view.bounds.width,
            height: view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height
        )
    }

    // MARK: - Layout

    private func buildLayout() {
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrimView.translatesAutoresizingMaskIntoConstraints = false
        largeIconView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true

        // Transparent-to-dark gradient behind the overlaid hero_banner text, so it stays
        // legible over any photo — matches the Android SDK's wynta_hero_scrim drawable.
        scrimLayer.colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.4).cgColor,
            UIColor.black.withAlphaComponent(0.8).cgColor
        ]
        scrimLayer.locations = [0, 0.5, 1]
        scrimView.layer.addSublayer(scrimLayer)
        scrimView.isHidden = true

        largeIconView.contentMode = .scaleAspectFill
        largeIconView.clipsToBounds = true
        largeIconView.layer.cornerRadius = 6
        largeIconView.isHidden = true

        titleLabel.font = .boldSystemFont(ofSize: 15)
        titleLabel.numberOfLines = 2

        bodyLabel.font = .systemFont(ofSize: 13)
        bodyLabel.numberOfLines = 4

        let textStack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(imageView)
        imageView.addSubview(scrimView)
        view.addSubview(largeIconView)
        view.addSubview(textStack)

        imageHeightConstraint = imageView.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageHeightConstraint,

            scrimView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            scrimView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            scrimView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),
            scrimView.heightAnchor.constraint(equalToConstant: Self.scrimHeight),

            largeIconView.centerYAnchor.constraint(equalTo: textStack.centerYAnchor),
            largeIconView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            largeIconView.widthAnchor.constraint(equalToConstant: Self.largeIconSize),
            largeIconView.heightAnchor.constraint(equalToConstant: Self.largeIconSize),

            textStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            textStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
        ])

        // "standard"/"branded" — text sits in normal document flow below the (zero-height,
        // unless branded shows a large icon's row) image area, trailing edge clear of the icon.
        textStackNormalConstraints = [
            textStack.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 12),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: largeIconView.leadingAnchor, constant: -12)
        ]

        // "hero_banner" — text overlays the bottom of the image, on top of the scrim, instead
        // of flowing below it.
        textStackOverlayConstraints = [
            textStack.topAnchor.constraint(greaterThanOrEqualTo: imageView.topAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ]

        NSLayoutConstraint.activate(textStackNormalConstraints)
    }

    private func attachedImage(in notification: UNNotification, identifier: String) -> UIImage? {
        guard let attachment = notification.request.content.attachments.first(where: { $0.identifier == identifier }),
              attachment.url.startAccessingSecurityScopedResource() else { return nil }
        defer { attachment.url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: attachment.url) else { return nil }
        return UIImage(data: data)
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
