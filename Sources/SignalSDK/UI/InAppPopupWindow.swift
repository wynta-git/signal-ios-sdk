import UIKit

internal typealias InAppInteractionHandler = (_ interactionType: String, _ ctaLabel: String?) -> Void

/// Renders a single in-app notification (image + tappable CTA baked into the image, plus a
/// close button) in its own overlay UIWindow, on top of whatever screen the host app currently
/// has open. No view controller presentation, no host app involvement. Ported from the React
/// Native SDK's ios/WyntaInAppPopupWindow.m.
internal final class InAppPopupWindow: NSObject {
    private var overlayWindow: UIWindow?
    // The window that was key before we took over — restored on dismiss. Without this,
    // the app's main window loses key status the moment the overlay becomes key, and
    // nothing gives it back afterward, leaving the whole app unresponsive to touch once
    // the popup is dismissed.
    private weak var previousKeyWindow: UIWindow?
    private var webViewWindow: InAppWebViewWindow?
    private var ctaValue: String?
    private var ctaLabel: String?
    private var interactionHandler: InAppInteractionHandler?
    private var resolved = false

    func present(
        imageURL imageURLString: String,
        ctaAction: String,
        ctaValue: String?,
        ctaLabel: String?,
        interactionHandler: @escaping InAppInteractionHandler
    ) {
        self.ctaValue = ctaValue
        self.ctaLabel = ctaLabel
        self.interactionHandler = interactionHandler

        // Both early-return paths below must still resolve via interactionHandler —
        // SignalSDK.swift only clears its popup-visible guard on a "clicked"/"dismissed"
        // callback. Without this, a bad image URL or a failed download would leave it stuck
        // true forever, silently blocking every later in-app popup for the rest of the
        // process lifetime.
        guard let url = URL(string: imageURLString) else {
            interactionHandler("dismissed", nil)
            return
        }

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            let image = data.flatMap { UIImage(data: $0) }
            DispatchQueue.main.async {
                guard let image else {
                    self?.interactionHandler?("dismissed", nil)
                    return
                }
                self?.show(image: image)
            }
        }
        task.resume()
    }

    private func show(image: UIImage) {
        var scene: UIWindowScene?
        for connectedScene in UIApplication.shared.connectedScenes {
            if let windowScene = connectedScene as? UIWindowScene,
               windowScene.activationState == .foregroundActive {
                scene = windowScene
                break
            }
        }

        let window: UIWindow
        if let scene {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: UIScreen.main.bounds)
        }
        window.frame = UIScreen.main.bounds
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        window.rootViewController = UIViewController()
        overlayWindow = window

        guard let root = window.rootViewController?.view else { return }
        root.backgroundColor = UIColor(white: 0, alpha: 0.35)
        root.alpha = 0

        let blurEffect = UIBlurEffect(style: .systemMaterialDark)
        let blurView = UIVisualEffectView(effect: blurEffect)
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

        // The shadow needs masksToBounds off on this container, so the rounded-corner
        // clip happens on the inner clipView instead.
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

        let imageView = UIImageView(frame: clipView.bounds)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.image = image
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        clipView.addSubview(imageView)

        let imageTap = UITapGestureRecognizer(target: self, action: #selector(handleImageTap))
        imageView.addGestureRecognizer(imageTap)

        // Centered exactly on the card's corner — half in, half out. Positioned in `root`'s
        // coordinate space and added as a SIBLING of `card` (not a subview of it): UIKit's
        // default hitTest rejects touches outside a view's own bounds before ever checking
        // its subviews, so a close button placed half above card.bounds (y < 0) would only
        // receive taps on its bottom half if it were a child of card. Matches the Android
        // port's InAppPopupOverlay.kt, which places its close button as a sibling for the
        // same reason.
        let closeSize: CGFloat = 32
        let closeButton = UIView(frame: CGRect(
            x: cardFrame.origin.x + cardWidth - closeSize / 2,
            y: cardFrame.origin.y - closeSize / 2,
            width: closeSize, height: closeSize
        ))
        closeButton.backgroundColor = .white
        closeButton.layer.cornerRadius = closeSize / 2
        closeButton.layer.shadowColor = UIColor.black.cgColor
        closeButton.layer.shadowOpacity = 0.3
        closeButton.layer.shadowOffset = CGSize(width: 0, height: 1)
        closeButton.layer.shadowRadius = 2
        // No longer a child of `card`, so it must animate in on its own — it used to inherit
        // card's fade/scale-in for free via view hierarchy alpha/transform propagation.
        closeButton.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        closeButton.alpha = 0

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

        let closeTap = UITapGestureRecognizer(target: self, action: #selector(handleClosePress))
        closeButton.addGestureRecognizer(closeTap)
        closeButton.isUserInteractionEnabled = true
        root.addSubview(closeButton)

        // makeKeyAndVisible (not just isHidden = false) is required for the overlay to
        // reliably receive touches — a merely-visible non-key window can be bypassed by
        // hit-testing in favor of the app's actual key window (see previousKeyWindow's
        // comment for why dismiss() must give key status back afterward).
        previousKeyWindow = scene?.windows.first(where: { $0.isKeyWindow })
        window.makeKeyAndVisible()

        UIView.animate(withDuration: 0.18) { root.alpha = 1 }
        UIView.animate(
            withDuration: 0.22, delay: 0,
            usingSpringWithDamping: 0.85, initialSpringVelocity: 0.3,
            options: .curveEaseOut,
            animations: {
                card.alpha = 1
                card.transform = .identity
                closeButton.alpha = 1
                closeButton.transform = .identity
            }
        )

        interactionHandler?("shown", nil)
    }

    @objc private func handleImageTap() {
        guard !resolved else { return }
        resolved = true

        // Present the web view (and let it retain itself — see InAppWebViewWindow) BEFORE
        // calling interactionHandler, since that call reports "clicked" up to SignalSDK,
        // which clears its currentPopup reference — the only thing keeping this instance
        // alive while its own method is still executing.
        if let ctaValue, !ctaValue.isEmpty {
            let webViewWindow = InAppWebViewWindow()
            self.webViewWindow = webViewWindow
            webViewWindow.present(urlString: ctaValue)
        }

        interactionHandler?("clicked", ctaLabel)

        dismiss()
    }

    @objc private func handleClosePress() {
        guard !resolved else { return }
        resolved = true

        interactionHandler?("dismissed", nil)

        dismiss()
    }

    private func dismiss() {
        overlayWindow?.isHidden = true
        overlayWindow = nil
        // Restore key status to the app's real window — see previousKeyWindow's comment.
        previousKeyWindow?.makeKeyAndVisible()
        previousKeyWindow = nil
    }
}
