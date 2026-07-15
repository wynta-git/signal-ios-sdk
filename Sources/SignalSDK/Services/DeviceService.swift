import UIKit

// Device info is captured once at init time (on the main thread via initSDK) to
// avoid repeated UIDevice accesses on background threads.
internal final class DeviceService {
    private let cachedInfo: DeviceInfo

    init() {
        let osVersion   = UIDevice.current.systemVersion
        let appVersion  = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let deviceModel = UIDevice.current.model   // "iPhone" or "iPad"
        let timezone    = TimeZone.current.identifier
        let locale      = Locale.current.identifier

        cachedInfo = DeviceInfo(
            platform:     "ios",
            os:           "iOS \(osVersion)",
            os_version:   osVersion,
            app_version:  appVersion,
            device_model: deviceModel,
            manufacturer: "Apple",
            timezone:     timezone,
            locale:       locale
        )
    }

    func getDeviceInfo() -> DeviceInfo { cachedInfo }
}
