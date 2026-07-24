import Foundation

internal final class NotificationInboxService {

    private static let timeoutInterval: TimeInterval = 10

    func fetchInbox(
        userId: String,
        clientId: String,
        clientSecret: String,
        baseUrl: String,
        completion: @escaping (InboxResponse?, String?) -> Void
    ) {
        guard let encodedUserId = userId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            completion(nil, "Invalid userId"); return
        }
        let inboxUrl = "\(baseUrl)/events/notifications/inbox?user_id=\(encodedUserId)&unread_only=true"
        guard let url = URL(string: inboxUrl) else {
            completion(nil, "Invalid URL"); return
        }

        var req = URLRequest(url: url, timeoutInterval: Self.timeoutInterval)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(clientId,     forHTTPHeaderField: "X-Client-Id")
        req.setValue(clientSecret, forHTTPHeaderField: "X-Client-Secret")

        Logger.log("fetchInbox → GET \(inboxUrl)")

        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error {
                Logger.error("fetchInbox failed: \(error.localizedDescription)")
                ApiLogger.fire(url: inboxUrl, method: "GET", requestBody: nil, responseStatus: nil, responseBody: nil)
                completion(nil, error.localizedDescription); return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let responseBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            Logger.log("fetchInbox ← \(status) | \(inboxUrl)")
            ApiLogger.fire(url: inboxUrl, method: "GET", requestBody: nil, responseStatus: status, responseBody: responseBody)

            guard (200...299).contains(status) else {
                completion(nil, "HTTP \(status): \(responseBody)"); return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(nil, "Invalid JSON response"); return
            }
            completion(Self.parseInboxResponse(json), nil)
        }.resume()
    }

    func markNotificationsRead(
        _ notificationIds: [String],
        userId: String,
        clientId: String,
        clientSecret: String,
        baseUrl: String,
        completion: @escaping (String?) -> Void
    ) {
        guard let encodedUserId = userId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            completion("Invalid userId"); return
        }
        let readUrl = "\(baseUrl)/events/notifications/read?user_id=\(encodedUserId)"
        guard let url = URL(string: readUrl) else {
            completion("Invalid URL"); return
        }

        let body: [String: Any] = ["notification_ids": notificationIds]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            completion("JSON serialization failed"); return
        }
        let requestBodyStr = String(data: bodyData, encoding: .utf8)

        var req = URLRequest(url: url, timeoutInterval: Self.timeoutInterval)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(clientId,     forHTTPHeaderField: "X-Client-Id")
        req.setValue(clientSecret, forHTTPHeaderField: "X-Client-Secret")
        req.httpBody = bodyData

        Logger.log("markNotificationsRead → POST \(readUrl)")

        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error {
                Logger.error("markNotificationsRead failed: \(error.localizedDescription)")
                ApiLogger.fire(url: readUrl, method: "POST", requestBody: requestBodyStr, responseStatus: nil, responseBody: nil)
                completion(error.localizedDescription); return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let responseBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            Logger.log("markNotificationsRead ← \(status) | \(readUrl)")
            ApiLogger.fire(url: readUrl, method: "POST", requestBody: requestBodyStr, responseStatus: status, responseBody: responseBody)
            if (200...299).contains(status) {
                completion(nil)
            } else {
                completion("HTTP \(status): \(responseBody)")
            }
        }.resume()
    }

    // ── JSON parsing ──────────────────────────────────────────────────────────

    private static func parseInboxResponse(_ json: [String: Any]) -> InboxResponse {
        let notificationsArray = json["notifications"] as? [[String: Any]] ?? []
        let notifications = notificationsArray.map(parseInboxNotification)
        return InboxResponse(
            notifications: notifications,
            next_cursor: json["next_cursor"] as? String,
            unread_count: json["unread_count"] as? Int ?? 0
        )
    }

    private static func parseInboxNotification(_ json: [String: Any]) -> InboxNotification {
        let mediaDict = json["media"] as? [String: Any]
        let ctaArray = json["cta"] as? [[String: Any]]
        return InboxNotification(
            notification_id: json["notification_id"] as? String ?? "",
            campaign_id: json["campaign_id"] as? String ?? "",
            media: mediaDict.map { NotificationMedia(image_url: $0["image_url"] as? String) },
            cta: ctaArray?.map(parseNotificationCta),
            expires_at: json["expires_at"] as? String,
            trigger_type: json["trigger_type"] as? String,
            target_screens: json["target_screens"] as? [String],
            target_events: json["target_events"] as? [String]
        )
    }

    private static func parseNotificationCta(_ json: [String: Any]) -> NotificationCta {
        NotificationCta(
            role: json["role"] as? String,
            label: json["label"] as? String,
            action: json["action"] as? String ?? "dismiss",
            value: json["value"] as? String
        )
    }
}
