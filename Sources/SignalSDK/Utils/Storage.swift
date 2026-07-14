import Foundation

internal enum StorageKey {
    static let apnsToken = "@signal/apns_token"
}

internal final class Storage {
    static let shared = Storage()
    private let defaults = UserDefaults.standard
    private init() {}

    func get(_ key: String) -> String? { defaults.string(forKey: key) }
    func set(_ key: String, _ value: String) { defaults.set(value, forKey: key) }
    func remove(_ key: String) { defaults.removeObject(forKey: key) }
}
