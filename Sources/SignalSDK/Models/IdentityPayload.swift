/// Payload passed to `SignalSDK.shared.setIdentity(_:completion:)`.
///
/// - Parameters:
///   - userId:      Logged-in user ID or anonymous UUID. At least one of `userId` or a previously
///                  stored identity must be present.
///   - anonymousId: Previous anonymous UUID (for stitching pre-login events on the backend).
///   - fcmToken:    APNs / FCM push token to register for this identity.
///   - traits:      Player profile traits.
///   - unsetTraits: Trait keys to remove from the backend profile.
///   - timestamp:   ISO-8601 timestamp; defaults to now if omitted.
public struct IdentityPayload {
    public let userId: String?
    public let anonymousId: String?
    public let fcmToken: String?
    public let traits: PlayerTraits?
    public let unsetTraits: [String]?
    public let timestamp: String?

    public init(
        userId: String? = nil,
        anonymousId: String? = nil,
        fcmToken: String? = nil,
        traits: PlayerTraits? = nil,
        unsetTraits: [String]? = nil,
        timestamp: String? = nil
    ) {
        self.userId = userId
        self.anonymousId = anonymousId
        self.fcmToken = fcmToken
        self.traits = traits
        self.unsetTraits = unsetTraits
        self.timestamp = timestamp
    }
}
