internal struct SDKState {
    var clientId: String?
    var clientSecret: String?
    var userId: String?
    var fcmToken: String?
    var initialized: Bool = false
    var appOpenTracked: Bool = false
    var baseUrl: String = "https://api.wynta.com/api/v1"
}
