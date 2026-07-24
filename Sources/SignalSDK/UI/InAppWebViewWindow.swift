import UIKit
import WebKit

/// Full-screen in-app browser for a notification CTA's `value` URL, in its own overlay
/// UIWindow. Presented only from InAppPopupWindow when a tapped CTA has a non-empty value —
/// never referenced by the host app. Ported from the React Native SDK's
/// ios/WyntaInAppWebViewWindow.m.
internal final class InAppWebViewWindow: NSObject {
    // Retains itself for as long as the web view is on screen. InAppPopupWindow (the caller)
    // is only kept alive by SignalSDK.currentPopup, which gets cleared as part of reporting
    // this same "clicked" interaction — so a plain `popup.webViewWindow` property isn't a
    // reliable owner, it can be torn down (along with this window) right as it's meant to
    // appear. Self-retention decouples this window's lifetime from the popup's.
    private static var current: InAppWebViewWindow?

    private var overlayWindow: UIWindow?

    func present(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        Self.current = self

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
        window.windowLevel = .alert + 2
        window.backgroundColor = .white
        window.rootViewController = UIViewController()
        overlayWindow = window

        guard let root = window.rootViewController?.view else { return }
        root.backgroundColor = .white

        let topInset = window.safeAreaInsets.top > 0 ? window.safeAreaInsets.top : 20
        let barHeight = topInset + 44

        let webView = WKWebView(frame: CGRect(
            x: 0, y: barHeight,
            width: root.bounds.width, height: root.bounds.height - barHeight
        ))
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.load(URLRequest(url: url))
        root.addSubview(webView)

        let closeSize: CGFloat = 32
        let closeButton = UIView(frame: CGRect(
            x: 12, y: topInset + (44 - closeSize) / 2,
            width: closeSize, height: closeSize
        ))
        closeButton.backgroundColor = UIColor(white: 0.93, alpha: 1.0)
        closeButton.layer.cornerRadius = closeSize / 2

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

        let closeTap = UITapGestureRecognizer(target: self, action: #selector(dismiss))
        closeButton.addGestureRecognizer(closeTap)
        closeButton.isUserInteractionEnabled = true
        root.addSubview(closeButton)

        window.isHidden = false
    }

    @objc private func dismiss() {
        overlayWindow?.isHidden = true
        overlayWindow = nil
        Self.current = nil
    }
}
