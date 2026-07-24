internal struct SDKState {
    var clientId: String?
    var clientSecret: String?
    var userId: String?
    var fcmToken: String?
    var initialized: Bool = false
    var appOpenTracked: Bool = false
    var baseUrl: String = "https://api.wynta.com/api/v1"

    // In-app notifications — session-only, reset on process restart (not persisted).
    var handledInAppNotificationIds: [String] = []
    var notificationCache: [InboxNotification] = []
    var isInAppPopupVisible: Bool = false
    var currentScreen: String?
    var previousScreen: String?
}
