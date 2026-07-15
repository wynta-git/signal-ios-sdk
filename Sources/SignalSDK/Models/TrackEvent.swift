internal struct TrackEvent {
    let event_id: String
    let event_name: String
    let schema_version: Int
    let user_id: String
    let session_id: String
    let timestamp: String
    let sdk: SdkInfo
    let device: DeviceInfo
    let properties: [String: Any]
}
