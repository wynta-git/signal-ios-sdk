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
///   - `standard`: plain title/body, no color, with an optional rich image above the text.
///   - `branded`: the whole card is filled with `accentColorHex`, rounded corners, with an
///     optional rich image above the text (no image beside the text).
///   - `hero_banner`: the image fills the card edge-to-edge at its own aspect ratio (no fixed
///     height, so it isn't cropped), with title/body overlaid in white directly at the bottom.
/// The collapsed banner is always OS-standard regardless of what's drawn here — only the
/// expanded/long-press view uses this UI, a platform constraint, not a bug.
open class PushNotificationContentViewController: UIViewController, UNNotificationContentExtension {

    // Matches the Android SDK's rounded-branded-card radius.
    private static let cardCornerRadius: CGFloat = 12
    // Wide marketing banners commonly run wider than 3:1 — a 120pt floor was forcing those
    // taller than their natural aspect ratio, and since scaleAspectFill fills both dimensions,
    // that extra height forced extra width to be cropped off the sides too (net effect: a
    // zoomed-in, hard-to-make-out image). Lowered so typical wide banners render closer to their
    // own aspect ratio instead of being stretched taller and cropped more.
    private static let minHeroHeight: CGFloat = 90
    private static let maxHeroHeight: CGFloat = 220
    // Rich image (standard/branded): inset inside the card, sized to its own aspect ratio,
    // capped so title/body still fit — same 160 cap as the Android layouts.
    private static let richImageInset: CGFloat = 12
    private static let richImageCornerRadius: CGFloat = 8
    private static let maxRichImageHeight: CGFloat = 160

    private let imageView = UIImageView()
    private let richImageView = UIImageView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()

    private var imageHeightConstraint: NSLayoutConstraint!
    private var richImageTopConstraint: NSLayoutConstraint!
    private var richImageHeightConstraint: NSLayoutConstraint!
    private var textStackNormalConstraints: [NSLayoutConstraint] = []
    private var textStackOverlayConstraints: [NSLayoutConstraint] = []

    override open func viewDidLoad() {
        super.viewDidLoad()
        view.layer.cornerRadius = Self.cardCornerRadius
        view.clipsToBounds = true
        buildLayout()
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
        richImageView.image = nil
        richImageView.isHidden = true
        richImageTopConstraint.constant = 0
        richImageHeightConstraint.constant = 0
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
            // Fixed black, not .label/.secondaryLabel — those are dynamic system colors that
            // flip to white in dark mode, which reads as invisible against a light campaign-
            // chosen background. The card's own background color is picked independently of the
            // device's system theme, so its text can't rely on system-theme-aware colors either.
            titleLabel.textColor = .black
            bodyLabel.textColor = .black
            showRichImage(in: notification)

        case "hero_banner":
            guard let image = attachedImage(in: notification, identifier: "hero_image") else {
                break // silent fallback to plain layout, per spec — no image, nothing to show
            }
            imageView.image = image

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
            showRichImage(in: notification) // "standard" — title/body, plus the rich image if any
        }

        // Applied after the per-template switch, unlike accentColorHex/imageUrl/richImageUrl,
        // so text_color overrides the default title/body color on all three templates rather
        // than being scoped to one.
        if let hex = payload?.textColor, let color = UIColor(hex: hex) {
            titleLabel.textColor = color
            bodyLabel.textColor = color
        }

        // Measured at the real card width — an unconstrained compressed-size fit lets the labels
        // lay out on one line and under-reports the height.
        let width = view.bounds.width > 0 ? view.bounds.width : 320
        preferredContentSize = CGSize(
            width: width,
            height: view.systemLayoutSizeFitting(
                CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height
        )
    }

    // MARK: - Layout

    private func buildLayout() {
        imageView.translatesAutoresizingMaskIntoConstraints = false
        richImageView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true

        richImageView.contentMode = .scaleAspectFill
        richImageView.clipsToBounds = true
        richImageView.layer.cornerRadius = Self.richImageCornerRadius
        richImageView.isHidden = true

        titleLabel.font = .boldSystemFont(ofSize: 15)
        titleLabel.numberOfLines = 2

        bodyLabel.font = .systemFont(ofSize: 13)
        bodyLabel.numberOfLines = 4

        let textStack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(imageView)
        view.addSubview(richImageView)
        view.addSubview(textStack)

        imageHeightConstraint = imageView.heightAnchor.constraint(equalToConstant: 0)
        // Both 0 while there's no rich image, so the text sits exactly where it did before.
        richImageTopConstraint = richImageView.topAnchor.constraint(equalTo: imageView.bottomAnchor)
        richImageHeightConstraint = richImageView.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageHeightConstraint,

            richImageTopConstraint,
            richImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Self.richImageInset),
            richImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Self.richImageInset),
            richImageHeightConstraint,

            textStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            textStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
        ])

        // "standard"/"branded" — text sits in normal document flow below the rich image
        // (zero-height when there isn't one).
        textStackNormalConstraints = [
            textStack.topAnchor.constraint(equalTo: richImageView.bottomAnchor, constant: 12),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16)
        ]

        // "hero_banner" — text overlays the bottom of the image instead of flowing below it.
        // The card's bottom is the image's bottom: without this, nothing ties the image to the
        // card's height, so the card was sized to the text alone and showed only a thin strip
        // of the banner (the image overflowed below and was clipped).
        textStackOverlayConstraints = [
            view.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: imageView.topAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ]

        NSLayoutConstraint.activate(textStackNormalConstraints)
    }

    // Standard/branded rich image, attached by PushNotificationExtensionHelper. Missing
    // attachment (no image, or the download failed) leaves the plain title/body layout.
    private func showRichImage(in notification: UNNotification) {
        guard let image = attachedImage(in: notification, identifier: "rich_image"),
              image.size.width > 0 else { return }
        richImageView.image = image
        richImageView.isHidden = false
        let cardWidth = view.bounds.width > 0 ? view.bounds.width : 320
        let width = cardWidth - 2 * Self.richImageInset
        richImageTopConstraint.constant = Self.richImageInset
        richImageHeightConstraint.constant = min(width * image.size.height / image.size.width, Self.maxRichImageHeight)
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
