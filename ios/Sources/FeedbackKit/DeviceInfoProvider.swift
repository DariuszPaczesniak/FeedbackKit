import Foundation

#if os(iOS)
import UIKit
#endif

public final class DeviceInfoProvider {
    public init() {}

    public func summary() -> String {
        var result = ""

        let bundle = Bundle.main
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        result += "App version: \(version) (\(build))\n"

        #if os(iOS)
        let device = UIDevice.current
        result += "Platform: iOS \(device.systemVersion)\n"
        result += "Device: \(device.model)\n"
        #else
        result += "Platform: Unknown\n"
        result += "Device: Unknown\n"
        #endif

        return result
    }
}
