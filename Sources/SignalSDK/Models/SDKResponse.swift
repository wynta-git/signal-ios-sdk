public struct SDKResponse {
    public let success: Bool
    public let accepted: Int?
    public let rejected: Int?
    public let error: String?

    public init(success: Bool, accepted: Int? = nil, rejected: Int? = nil, error: String? = nil) {
        self.success = success
        self.accepted = accepted
        self.rejected = rejected
        self.error = error
    }
}
