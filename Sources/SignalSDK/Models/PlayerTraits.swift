/// Player profile traits sent with `SignalSDK.shared.setIdentity(_:)`.
/// All fields are optional. Use `custom` for any non-standard key-value pairs.
public struct PlayerTraits {
    public let email: String?
    public let phone: String?
    public let firstName: String?
    public let lastName: String?
    public let dateOfBirth: String?
    public let country: String?
    public let currency: String?
    public let language: String?
    public let kycStatus: String?
    public let vipLevel: String?
    public let accountStatus: String?
    public let registrationDate: String?
    public let brandId: String?
    public let custom: [String: Any]

    public init(
        email: String? = nil,
        phone: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        dateOfBirth: String? = nil,
        country: String? = nil,
        currency: String? = nil,
        language: String? = nil,
        kycStatus: String? = nil,
        vipLevel: String? = nil,
        accountStatus: String? = nil,
        registrationDate: String? = nil,
        brandId: String? = nil,
        custom: [String: Any] = [:]
    ) {
        self.email = email
        self.phone = phone
        self.firstName = firstName
        self.lastName = lastName
        self.dateOfBirth = dateOfBirth
        self.country = country
        self.currency = currency
        self.language = language
        self.kycStatus = kycStatus
        self.vipLevel = vipLevel
        self.accountStatus = accountStatus
        self.registrationDate = registrationDate
        self.brandId = brandId
        self.custom = custom
    }
}
