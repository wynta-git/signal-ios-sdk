import Foundation

internal final class SessionService {
    static let shared = SessionService()
    private var sessionId: String?
    private let lock = NSLock()

    private init() {}

    func getSessionId() -> String {
        lock.lock(); defer { lock.unlock() }
        if let id = sessionId { return id }
        let id = UUID().uuidString.lowercased()
        sessionId = id
        return id
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        sessionId = nil
    }
}
