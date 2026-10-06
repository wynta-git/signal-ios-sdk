import UIKit

internal typealias InAppInteractionHandler = (
    _ interactionType: String,
    _ ctaLabel: String?,
    _ ctaAction: String?,
    _ ctaValue: String?
) -> Void

private let defaultCtaColor = UIColor(red: 0.184, green: 0.420, blue: 1.0, alpha: 1.0) // #2F6BFF

/// Renders a single in-app notification in its own overlay `UIWindow`, on top of whatever
/// screen the host app currently has open. No view controller presentation, no host app
/// involvement — this keeps the host's own view controller lifecycle undisturbed, the same
/// reason the Android SDK attaches its popup to the content view rather than starting a new
/// Activity.
///
/// `template_type` selects the shape: "full_screen" (covers the whole screen, opaque
/// background), "pop_ups" (centered card over a dim scrim), "bubble" (small card anchored to
/// the bottom, no scrim — app content stays visible/interactive around it). Any other/missing
/// value falls back to the original fixed image-card layout this SDK originally shipped with,
/// preserving exact behavior for already-scheduled campaigns that predate this field.
///
/// image/title/body/cta are each shown only when present in the payload.
internal final class InAppPopupWindow: NSObject {
    private var overlayWindow: UIWindow?
    // The window that was key before we took over — restored on dismiss. Without this,
    // the app's main window loses key status the moment the overlay becomes key, and
    // nothing gives it back afterward, leaving the whole app unresponsive to touch once
    // the popup is dismissed.
    private weak var previousKeyWindow: UIWindow?
    private var webViewWindow: InAppWebViewWindow?
    private var resolver: InteractionResolver?

    func present(notification: InboxNotification, interactionHandler: @escaping InAppInteractionHandler) {
        resolver = InteractionResolver(
            notificationId: notification.notification_id,
            onResolved: interactionHandler,
            openUrl: { [weak self] urlString in self?.openWebView(urlString) },
            dismiss: { [weak self] in self?.dismiss() }
        )

        if notification.render_engine == "html" {
            // No WebView-based renderer yet — drop rather than show nothing useful.
            Logger.log("InAppPopupWindow.present: render_engine=html not supported yet — dismissing \(notification.notification_id)")
            resolver?.dismissByUser()
            return
        }

        guard let imageUrlString = notification.media?.image_url, !imageUrlString.isEmpty else {
            show(image: nil, notification: notification)
            return
        }
        guard let url = URL(string: imageUrlString) else {
            show(image: nil, notification: notification)
            return
        }

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            let image = data.flatMap { UIImage(data: $0) }
            DispatchQueue.main.async {
                self?.show(image: image, notification: notification)
            }
        }
        task.resume()
    }

    private func openWebView(_ urlString: String) {
        let webViewWindow = InAppWebViewWindow()
        self.webViewWindow = webViewWindow
        webViewWindow.present(urlString: urlString)
    }

    private func foregroundScene() -> UIWindowScene? {
        for connectedScene in UIApplication.shared.connectedScenes {
            if let windowScene = connectedScene as? UIWindowScene,
               windowScene.activationState == .foregroundActive {
                return windowScene
            }
        }
        return nil
    }

    private func makeOverlayWindow() -> (window: UIWindow, root: UIView) {
        let scene = foregroundScene()
        let window: UIWindow = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        window.frame = UIScreen.main.bounds
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        window.rootViewController = UIViewController()
        overlayWindow = window
        return (window, window.rootViewController!.view)
    }

    private func presentWindow(_ window: UIWindow) {
        previousKeyWindow = foregroundScene()?.windows.first(where: { $0.isKeyWindow })
        window.makeKeyAndVisible()
    }

    private func show(image: UIImage?, notification: InboxNotification) {
        guard let resolver else { return }
        switch notification.template_type {
        case "full_screen":
            showFullScreen(image: image, notification: notification, resolver: resolver)
        case "pop_ups":
            showCard(image: image, notification: notification, resolver: resolver, bubble: false)
        case "bubble":
            showCard(image: image, notification: notification, resolver: resolver, bubble: true)
        default:
            showLegacyImageCard(image: image, notification: notification, resolver: resolver)
        }
    }

    // ── Shared layout helpers ────────────────────────────────────────────────────────────

    private func measuredLabel(text: String, font: UIFont, color: UIColor, width: CGFloat, maxLines: Int) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = font
        label.textColor = color
        label.textAlignment = .center
        label.numberOfLines = maxLines
        let size = label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        label.frame = CGRect(x: 0, y: 0, width: width, height: ceil(size.height))
        return label
    }

    private func makeCtaButton(_ cta: NotificationCta, width: CGFloat, resolver: InteractionResolver) -> UIControl {
        // ClosureButton, not UIAction/addAction(_:for:) — this SDK's deployment target is
        // iOS 13, and addAction requires iOS 14.
        let button = ClosureButton(frame: CGRect(x: 0, y: 0, width: width, height: 44)) {
            resolver.click(cta)
        }
        button.backgroundColor = UIColor(hex: cta.cta_background_color ?? "") ?? defaultCtaColor
        button.layer.cornerRadius = 8
        button.layer.masksToBounds = true

        let label = UILabel(frame: button.bounds)
        label.text = cta.label
        label.textColor = .white
        label.font = .boldSystemFont(ofSize: 15)
        label.textAlignment = .center
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        label.isUserInteractionEnabled = false
        button.addSubview(label)

        return button
    }

    // Lays out image (optional)/title (optional)/body (optional)/cta rows (0+) top-to-bottom
    // inside a container of the given width, returning the container sized to fit its content.
    private func buildContentStack(
        notification: InboxNotification,
        image: UIImage?,
        width: CGFloat,
        imageHeight: CGFloat,
        imageCornerRadius: CGFloat,
        resolver: InteractionResolver
    ) -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 0))
        var y: CGFloat = 0

        if let image {
            let imageView = UIImageView(frame: CGRect(x: 0, y: y, width: width, height: imageHeight))
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.layer.cornerRadius = imageCornerRadius
            imageView.image = image
            container.addSubview(imageView)
            y += imageHeight + 12
        }
        if let title = notification.title, !title.isEmpty {
            let label = measuredLabel(text: title, font: .boldSystemFont(ofSize: 21), color: UIColor(hex: "#1A1A1A")!, width: width, maxLines: 3)
            label.frame.origin.y = y
            container.addSubview(label)
            y += label.frame.height + 30
        }
        if let body = notification.body, !body.isEmpty {
            let label = measuredLabel(text: body, font: .systemFont(ofSize: 18), color: UIColor(hex: "#6B6B6B")!, width: width, maxLines: 4)
            label.frame.origin.y = y
            container.addSubview(label)
            y += label.frame.height + 38
        }
        let ctaList = (notification.cta ?? []).filter { !($0.label?.isEmpty ?? true) }
        for cta in ctaList {
            let button = makeCtaButton(cta, width: width, resolver: resolver)
            button.frame.origin.y = y
            container.addSubview(button)
            y += button.frame.height + 8
        }
        if !ctaList.isEmpty { y -= 8 } // drop the trailing gap after the last button

        container.frame.size.height = y
        return container
    }

    // Centered exactly on the container's top-end corner. Matches the Android port's own
    // close-button placement — a child of the card/container it closes, not an absolutely
    // positioned sibling, so it stays correctly placed regardless of final content size.
    private func makeCloseButton(target: AnyObject, action: Selector) -> UIView {
        let closeSize: CGFloat = 28
        let closeButton = UIView(frame: CGRect(x: 0, y: 0, width: closeSize, height: closeSize))
        closeButton.backgroundColor = .white
        closeButton.layer.cornerRadius = closeSize / 2
        closeButton.layer.shadowColor = UIColor.black.cgColor
        closeButton.layer.shadowOpacity = 0.3
        closeButton.layer.shadowOffset = CGSize(width: 0, height: 1)
        closeButton.layer.shadowRadius = 2

        let barLength: CGFloat = 12
        let barThickness: CGFloat = 1.6
        let barColor = UIColor(red: 0.29, green: 0.29, blue: 0.29, alpha: 1.0)
        let bar1 = UIView(frame: CGRect(x: (closeSize - barLength) / 2, y: (closeSize - barThickness) / 2, width: barLength, height: barThickness))
        bar1.backgroundColor = barColor
        bar1.transform = CGAffineTransform(rotationAngle: .pi / 4)
        let bar2 = UIView(frame: CGRect(x: (closeSize - barLength) / 2, y: (closeSize - barThickness) / 2, width: barLength, height: barThickness))
        bar2.backgroundColor = barColor
        bar2.transform = CGAffineTransform(rotationAngle: -.pi / 4)
        closeButton.addSubview(bar1)
        closeButton.addSubview(bar2)

        let tap = UITapGestureRecognizer(target: target, action: action)
        closeButton.addGestureRecognizer(tap)
        closeButton.isUserInteractionEnabled = true
        return closeButton
    }

    private func showsCloseButton(_ notification: InboxNotification) -> Bool {
        notification.close_button_visibility != "never"
    }

    @objc private func handleClosePress() {
        resolver?.dismissByUser()
    }

    // ── Template: full_screen ────────────────────────────────────────────────────────────

    private func showFullScreen(image: UIImage?, notification: InboxNotification, resolver: InteractionResolver) {
        let (window, root) = makeOverlayWindow()
        root.backgroundColor = UIColor(hex: notification.media?.background_color ?? "") ?? .white
        root.alpha = 0

        let padding: CGFloat = 24
        let contentWidth = root.bounds.width - padding * 2
        let imageHeight = root.bounds.height * 0.35

        let content = buildContentStack(
            notification: notification, image: image, width: contentWidth,
            imageHeight: imageHeight, imageCornerRadius: 0, resolver: resolver
        )
        // With an image, the 45%-height image anchors the block near the top and centering the
        // whole thing reads as balanced. Without one, centering leaves a large empty gap above
        // the title — anchor to the top (clearing the close button) instead in that case.
        if image != nil {
            content.center = CGPoint(x: root.bounds.midX, y: root.bounds.midY)
        } else {
            content.center.x = root.bounds.midX
            content.frame.origin.y = window.safeAreaInsets.top + 80
        }
        root.addSubview(content)

        if showsCloseButton(notification) {
            let closeButton = makeCloseButton(target: self, action: #selector(handleClosePress))
            closeButton.frame.origin = CGPoint(x: root.bounds.width - closeButton.frame.width - 16, y: window.safeAreaInsets.top + 8)
            root.addSubview(closeButton)
        }

        presentWindow(window)
        UIView.animate(withDuration: 0.18) { root.alpha = 1 }
        resolver.reportShown()
    }

    // ── Templates: pop_ups / bubble (share the same "card" shape, different size/position) ──

    private func showCard(image: UIImage?, notification: InboxNotification, resolver: InteractionResolver, bubble: Bool) {
        let (window, root) = makeOverlayWindow()
        // pop_ups dims the app behind the card; bubble leaves it visible/interactive — a plain
        // clear-background UIView lets touches outside its subviews pass to the window below
        // once this overlay window isn't key... but since this window IS key (needed for the
        // card itself to receive touches), an explicitly clear root with no gesture recognizer
        // of its own simply doesn't intercept hit-testing outside its subviews' frames.
        root.backgroundColor = bubble ? .clear : UIColor(white: 0, alpha: 0.65)
        root.alpha = 0

        let screenWidth = root.bounds.width
        let cardWidth = bubble ? min(screenWidth * 0.9, 360) : screenWidth * 0.85
        let padding: CGFloat = 16
        let contentWidth = cardWidth - padding * 2

        let content = buildContentStack(
            notification: notification, image: image, width: contentWidth,
            imageHeight: bubble ? 120 : 140, imageCornerRadius: 10, resolver: resolver
        )
        content.frame.origin = CGPoint(x: padding, y: padding)
        let cardHeight = content.frame.maxY + padding

        // Shadow needs masksToBounds off on this container, so the rounded-corner clip (and
        // background fill) happens on the inner `cardBody` instead — matching the legacy
        // layout's card/clipView split, for the same reason (masksToBounds would otherwise
        // clip the shadow itself, since it draws outside the view's own bounds).
        let card = UIView(frame: CGRect(x: 0, y: 0, width: cardWidth, height: cardHeight))
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.25
        card.layer.shadowOffset = CGSize(width: 0, height: 6)
        card.layer.shadowRadius = 16
        card.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        card.alpha = 0

        let cardBody = UIView(frame: card.bounds)
        cardBody.backgroundColor = UIColor(hex: notification.media?.background_color ?? "") ?? .white
        cardBody.layer.cornerRadius = 16
        cardBody.layer.masksToBounds = true
        cardBody.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        card.addSubview(cardBody)
        cardBody.addSubview(content)

        if showsCloseButton(notification) {
            let closeButton = makeCloseButton(target: self, action: #selector(handleClosePress))
            closeButton.frame.origin = CGPoint(x: card.bounds.width - closeButton.frame.width - 8, y: 8)
            cardBody.addSubview(closeButton)
        }

        if bubble {
            // Float above the home indicator / gesture area, not flush against the raw window
            // edge — `root.bounds` is the full window, not inset by the safe area.
            let bottomInset: CGFloat = window.safeAreaInsets.bottom
            card.center = CGPoint(x: root.bounds.midX, y: root.bounds.height - 28 - bottomInset - card.frame.height / 2)
        } else {
            card.center = CGPoint(x: root.bounds.midX, y: root.bounds.midY)
        }
        root.addSubview(card)

        presentWindow(window)
        UIView.animate(withDuration: 0.18) { root.alpha = 1 }
        UIView.animate(
            withDuration: 0.22, delay: 0,
            usingSpringWithDamping: 0.85, initialSpringVelocity: 0.3,
            options: .curveEaseOut,
            animations: { card.alpha = 1; card.transform = .identity }
        )
        resolver.reportShown()
    }

    // ── Legacy fallback — unchanged behavior for nil/unrecognized template_type ──────────

    private func showLegacyImageCard(image: UIImage?, notification: InboxNotification, resolver: InteractionResolver) {
        guard let image else {
            Logger.log("InAppPopupWindow.showLegacyImageCard: no image — dismissing \(notification.notification_id)")
            resolver.dismissByUser()
            return
        }

        let (window, root) = makeOverlayWindow()
        root.backgroundColor = UIColor(white: 0, alpha: 0.35)
        root.alpha = 0

        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
        blurView.frame = root.bounds
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        root.addSubview(blurView)

        let cardWidth = root.bounds.width * 0.85
        let cardHeight = cardWidth * (image.size.height / image.size.width)
        let cardFrame = CGRect(
            x: (root.bounds.width - cardWidth) / 2,
            y: (root.bounds.height - cardHeight) / 2,
            width: cardWidth, height: cardHeight
        )

        let card = UIView(frame: cardFrame)
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.35
        card.layer.shadowOffset = CGSize(width: 0, height: 6)
        card.layer.shadowRadius = 16
        card.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        card.alpha = 0
        root.addSubview(card)

        let clipView = UIView(frame: card.bounds)
        clipView.layer.cornerRadius = 16
        clipView.layer.masksToBounds = true
        clipView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        card.addSubview(clipView)

        // The single legacy CTA (if any) — tapping the whole image acts as this button, since
        // this layout predates having a visible button row at all.
        let legacyCta = notification.cta?.first ?? NotificationCta(role: nil, label: nil, action: "dismiss", value: nil, cta_background_color: nil)
        let imageView = UIImageView(frame: clipView.bounds)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.image = image
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        clipView.addSubview(imageView)
        imageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleLegacyImageTap)))
        legacyResolver = resolver
        legacyCtaForTap = legacyCta

        let closeButton = makeCloseButton(target: self, action: #selector(handleClosePress))
        closeButton.frame.origin = CGPoint(x: cardFrame.maxX - closeButton.frame.width / 2, y: cardFrame.minY - closeButton.frame.height / 2)
        closeButton.alpha = 0
        closeButton.isHidden = !showsCloseButton(notification)
        closeButton.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        root.addSubview(closeButton)

        presentWindow(window)
        UIView.animate(withDuration: 0.18) { root.alpha = 1 }
        UIView.animate(
            withDuration: 0.22, delay: 0,
            usingSpringWithDamping: 0.85, initialSpringVelocity: 0.3,
            options: .curveEaseOut,
            animations: {
                card.alpha = 1
                card.transform = .identity
                if self.showsCloseButton(notification) {
                    closeButton.alpha = 1
                    closeButton.transform = .identity
                }
            }
        )
        resolver.reportShown()
    }

    // UITapGestureRecognizer's target/action can't carry the cta value directly — stashed here
    // for the duration of the legacy popup's lifetime only.
    private var legacyResolver: InteractionResolver?
    private var legacyCtaForTap: NotificationCta?

    @objc private func handleLegacyImageTap() {
        guard let cta = legacyCtaForTap else { return }
        legacyResolver?.click(cta)
    }

    private func dismiss() {
        overlayWindow?.isHidden = true
        overlayWindow = nil
        previousKeyWindow?.makeKeyAndVisible()
        previousKeyWindow = nil
        legacyResolver = nil
        legacyCtaForTap = nil
    }
}

// ── Shared interaction handling ──────────────────────────────────────────────────────────

// One per shown popup — `resolved` is shared across every button/close-tap so only the first
// interaction is ever reported, whichever element the user happened to tap.
private final class InteractionResolver {
    private let notificationId: String
    private let onResolved: InAppInteractionHandler
    private let openUrl: (String) -> Void
    private let dismissWindow: () -> Void
    private var resolved = false

    init(notificationId: String, onResolved: @escaping InAppInteractionHandler, openUrl: @escaping (String) -> Void, dismiss: @escaping () -> Void) {
        self.notificationId = notificationId
        self.onResolved = onResolved
        self.openUrl = openUrl
        self.dismissWindow = dismiss
    }

    func reportShown() {
        onResolved("shown", nil, nil, nil)
    }

    func click(_ cta: NotificationCta) {
        guard !resolved else { return }
        resolved = true
        Logger.log("InAppPopupWindow: clicked \(notificationId) (action=\(cta.action))")

        // Present the web view (and let it retain itself) BEFORE reporting "clicked" — that
        // call can clear whatever retains this popup, same ordering reasoning as before.
        if cta.action == "external_url", let value = cta.value, !value.isEmpty {
            openUrl(value)
        }
        onResolved("clicked", cta.label, cta.action, cta.value)
        // "deep_link" is handed to the host app's InAppActionHandler by SignalSDK.swift's
        // onInAppInteraction — nothing further to do here.
        dismissWindow()
    }

    func dismissByUser() {
        guard !resolved else { return }
        resolved = true
        Logger.log("InAppPopupWindow: dismissed \(notificationId)")
        onResolved("dismissed", nil, nil, nil)
        dismissWindow()
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

// UIControl.addAction(_:for:) requires iOS 14; this SDK's deployment target is iOS 13, so CTA
// buttons use this plain target-action wrapper instead, letting each button carry its own
// per-tap closure despite multiple buttons existing at once in the same popup.
private final class ClosureButton: UIControl {
    private let action: () -> Void

    init(frame: CGRect, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: frame)
        addTarget(self, action: #selector(handleTap), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @objc private func handleTap() {
        action()
    }
}
