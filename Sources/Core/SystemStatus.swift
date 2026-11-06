import Foundation
import IOKit
import IOKit.ps

/// 电源快照。
struct PowerSnapshot: Equatable {
    var onAC = true
    var hasBattery = false
    var percent: Int?
    var charging = false

    var isOnBattery: Bool { hasBattery && !onAC }

    var sourceText: String {
        if !hasBattery { return "电源适配器" }
        return onAC ? (charging ? "正在充电" : "电源适配器") : "电池供电"
    }

    var detailText: String {
        guard let percent else { return sourceText }
        return "\(sourceText) · \(percent)%"
    }
}

/// 机盖 / 电源等只读硬件状态。
enum SystemStatus {
    /// 机盖是否合上；读不到返回 nil。
    static func isLidClosed() -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        guard let property = IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        ) else { return nil }

        return property.takeRetainedValue() as? Bool
    }

    /// 当前电源与电量。
    static func power() -> PowerSnapshot {
        var snapshot = PowerSnapshot()

        if let type = IOPSGetProvidingPowerSourceType(nil)?.takeRetainedValue() as String? {
            snapshot.onAC = (type == (kIOPSACPowerValue as String))
        }

        guard
            let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return snapshot }

        for source in sources {
            guard
                let unmanaged = IOPSGetPowerSourceDescription(blob, source),
                let description = unmanaged.takeUnretainedValue() as? [String: Any]
            else { continue }

            guard (description[kIOPSTypeKey] as? String) == (kIOPSInternalBatteryType as String) else { continue }
            snapshot.hasBattery = true

            let current = description[kIOPSCurrentCapacityKey] as? Int
            let maximum = description[kIOPSMaxCapacityKey] as? Int
            if let current, let maximum, maximum > 0 {
                snapshot.percent = Int((Double(current) / Double(maximum) * 100).rounded())
            }
            snapshot.charging = (description[kIOPSIsChargingKey] as? Bool) ?? false
            if let state = description[kIOPSPowerSourceStateKey] as? String {
                snapshot.onAC = (state == (kIOPSACPowerValue as String))
            }
        }

        return snapshot
    }
}
