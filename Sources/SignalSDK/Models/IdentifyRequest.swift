internal struct IdentifyRequest {
    let user_id: String
    let anonymous_id: String?
    let traits: [String: Any]?
    let unset_traits: [String]?
    let timestamp: String
}
