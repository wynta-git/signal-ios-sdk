import Foundation

internal final class Logger {
    private static let tag = "[SignalSDK]"
    private static var _enabled = false
    private static let lock = NSLock()

    static func enable() {
        lock.lock(); defer { lock.unlock() }
        _enabled = true
    }

    static func log(_ message: String) {
        lock.lock(); let on = _enabled; lock.unlock()
        guard on else { return }
        print("\(tag) \(message)")
    }

    static func error(_ message: String) {
        lock.lock(); let on = _enabled; lock.unlock()
        guard on else { return }
        print("\(tag) ERROR: \(message)")
    }
}
