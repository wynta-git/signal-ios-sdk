/// Configuration passed to `SignalSDK.shared.initSDK(config:)`.
public struct SignalConfig {
    public let clientId: String
    public let clientSecret: String
    /// When `true`, the SDK prints debug logs to the console.
    public let debug: Bool
    /// Optional callback fired after every outbound API request. Useful for debugging and monitoring.
    public let onApiLog: ((ApiLogEntry) -> Void)?

    public init(
        clientId: String,
        clientSecret: String,
        debug: Bool = false,
        onApiLog: ((ApiLogEntry) -> Void)? = nil
    ) {
        self.clientId     = clientId
        self.clientSecret = clientSecret
        self.debug        = debug
        self.onApiLog     = onApiLog
    }
}
