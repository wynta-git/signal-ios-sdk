import Foundation

internal final class IdentityService {

    private static let timeoutInterval: TimeInterval = 10

    func identifyPlayer(
        _ request: IdentifyRequest,
        clientId: String,
        clientSecret: String,
        baseUrl: String,
        completion: @escaping (SDKResponse) -> Void
    ) {
        let identifyUrl = "\(baseUrl)/events/identify"
        guard let url = URL(string: identifyUrl) else {
            completion(SDKResponse(success: false, error: "Invalid URL")); return
        }

        var body: [String: Any] = [
            "user_id":   request.user_id,
            "timestamp": request.timestamp
        ]
        if let anon = request.anonymous_id { body["anonymous_id"] = anon }
        if let traits = request.traits, !traits.isEmpty { body["traits"] = traits }
        if let unset = request.unset_traits, !unset.isEmpty { body["unset_traits"] = unset }

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

        Logger.log("setIdentity → POST \(identifyUrl)")

        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error {
                Logger.error("identifyPlayer failed: \(error.localizedDescription)")
                ApiLogger.fire(url: identifyUrl, method: "POST", requestBody: requestBodyStr, responseStatus: nil, responseBody: nil)
                completion(SDKResponse(success: false, error: error.localizedDescription)); return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let responseBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            Logger.log("setIdentity ← \(status) | \(identifyUrl)")
            ApiLogger.fire(url: identifyUrl, method: "POST", requestBody: requestBodyStr, responseStatus: status, responseBody: responseBody)
            if (200...299).contains(status) {
                completion(SDKResponse(success: true))
            } else {
                completion(SDKResponse(success: false, error: "HTTP \(status): \(responseBody)"))
            }
        }.resume()
    }
}
