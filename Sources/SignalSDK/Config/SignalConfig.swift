/// Configuration passed to `SignalSDK.shared.initSDK(config:)`.
public struct SignalConfig {
    public let clientId: String
    public let clientSecret: String
    /// When `true`, the SDK prints debug logs to the console.
    public let debug: Bool

    public init(clientId: String, clientSecret: String, debug: Bool = false) {
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.debug = debug
    }
}
