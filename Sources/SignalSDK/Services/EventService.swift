import Foundation

internal final class EventService {

    private static let sdkName         = "signal-ios-sdk"
    private static let sdkVersion      = "1.0.0"
    private static let timeoutInterval: TimeInterval = 10

    private static let reservedKeys: Set<String> = [
        "user_id", "session_id", "event_id", "event_name",
        "timestamp", "schema_version", "sdk", "device"
    ]

    private let deviceService: DeviceService
    private let sdkInfo: SdkInfo

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale     = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        f.timeZone   = TimeZone(identifier: "UTC")
        return f
    }()

    init(deviceService: DeviceService) {
        self.deviceService = deviceService
        self.sdkInfo = SdkInfo(name: Self.sdkName, version: Self.sdkVersion)
    }

    func buildEvent(eventName: String, properties: [String: Any], userId: String) -> TrackEvent {
        let filtered = properties.filter { !Self.reservedKeys.contains($0.key) }
        return TrackEvent(
            event_id:       UUID().uuidString.lowercased(),
            event_name:     eventName,
            schema_version: 1,
            user_id:        userId,
            session_id:     SessionService.shared.getSessionId(),
            timestamp:      Self.isoFormatter.string(from: Date()),
            sdk:            sdkInfo,
            device:         deviceService.getDeviceInfo(),
            properties:     filtered
        )
    }

    func trackEvent(
        _ event: TrackEvent,
        clientId: String,
        clientSecret: String,
        baseUrl: String,
        completion: @escaping (SDKResponse) -> Void
    ) {
        let trackUrl = "\(baseUrl)/events/track"
        guard let url = URL(string: trackUrl) else {
            completion(SDKResponse(success: false, error: "Invalid URL")); return
        }

        let body: [String: Any] = ["events": [eventToDict(event)]]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(SDKResponse(success: false, error: "JSON serialization failed")); return
        }

        let requestBodyStr = String(data: bodyData, encoding: .utf8)

        var req = URLRequest(url: url, timeoutInterval: Self.timeoutInterval)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(clientId,     forHTTPHeaderField: "X-Client-Id")
        req.setValue(clientSecret, forHTTPHeaderField: "X-Client-Secret")
        req.httpBody = bodyData

        Logger.log("trackEvent → POST \(trackUrl)")

        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error {
                Logger.error("trackEvent failed: \(error.localizedDescription)")
                ApiLogger.fire(url: trackUrl, method: "POST", requestBody: requestBodyStr, responseStatus: nil, responseBody: nil)
                completion(SDKResponse(success: false, error: error.localizedDescription)); return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let responseBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            Logger.log("trackEvent ← \(status) | \(trackUrl)")
            ApiLogger.fire(url: trackUrl, method: "POST", requestBody: requestBodyStr, responseStatus: status, responseBody: responseBody)
            if (200...299).contains(status),
               let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                completion(SDKResponse(
                    success:  true,
                    accepted: json["accepted"] as? Int,
                    rejected: json["rejected"] as? Int
                ))
            } else {
                completion(SDKResponse(success: false, error: "HTTP \(status): \(responseBody)"))
            }
        }.resume()
    }

    // ── JSON helpers ──────────────────────────────────────────────────────────

    private func eventToDict(_ event: TrackEvent) -> [String: Any] {
        [
            "event_id":       event.event_id,
            "event_name":     event.event_name,
            "schema_version": event.schema_version,
            "user_id":        event.user_id,
            "session_id":     event.session_id,
            "timestamp":      event.timestamp,
            "sdk": [
                "name":    event.sdk.name,
                "version": event.sdk.version
            ] as [String: Any],
            "device":     deviceToDict(event.device),
            "properties": event.properties
        ]
    }

    private func deviceToDict(_ d: DeviceInfo) -> [String: Any] {
        var dict: [String: Any] = ["platform": d.platform, "os": d.os]
        if let v = d.os_version   { dict["os_version"]   = v }
        if let v = d.app_version  { dict["app_version"]  = v }
        if let v = d.device_model { dict["device_model"] = v }
        if let v = d.manufacturer { dict["manufacturer"] = v }
        if let v = d.timezone     { dict["timezone"]     = v }
        if let v = d.locale       { dict["locale"]       = v }
        return dict
    }
}
