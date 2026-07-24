import UIKit

// PLATFORM LIMITATIONS
// willEnterForeground — fires ONLY when returning from background, NOT on cold launch.
//   Cold-launch app_opened is handled by the first setIdentity() call.
// willTerminate — best-effort; NOT fired on force-quit (swipe-up kill) or OOM kill.
// session_ended — fired on didEnterBackground as the closest reliable proxy.
internal final class LifecycleService {
    private let getState: () -> SDKState
    private let emit: (String) -> Void
    private let checkInbox: () -> Void
    private var observers: [NSObjectProtocol] = []

    init(
        getState: @escaping () -> SDKState,
        emit: @escaping (String) -> Void,
        checkInbox: @escaping () -> Void = {}
    ) {
        self.getState = getState
        self.emit = emit
        self.checkInbox = checkInbox
    }

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default

        observers.append(center.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let s = self.getState()
            guard s.initialized && s.appOpenTracked else { return }
            Logger.log("Lifecycle → app_foreground")
            self.emit("app_foreground")
            self.checkInbox()
        })

        observers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let s = self.getState()
            guard s.initialized else { return }
            Logger.log("Lifecycle → app_background + session_ended")
            self.emit("app_background")
            self.emit("session_ended")
        })

        observers.append(center.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let s = self.getState()
            guard s.initialized else { return }
            Logger.log("Lifecycle → app_terminated")
            self.emit("app_terminated")
        })

        Logger.log("LifecycleService started")
    }

    func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        Logger.log("LifecycleService stopped")
    }
}
