import Foundation

/// Describes a single API call made by the SDK. Delivered to the `onApiLog` callback in `SignalConfig`.
public struct ApiLogEntry {
    public let url: String
    public let method: String
    public let requestBody: String?
    public let responseStatus: Int?
    public let responseBody: String?
}

internal enum ApiLogger {
    static var callback: ((ApiLogEntry) -> Void)?

    static func fire(
        url: String,
        method: String,
        requestBody: String?,
        responseStatus: Int?,
        responseBody: String?
    ) {
        guard let cb = callback else { return }
        let entry = ApiLogEntry(
            url: url, method: method,
            requestBody: requestBody,
            responseStatus: responseStatus,
            responseBody: responseBody
        )
        DispatchQueue.main.async { cb(entry) }
    }
}
