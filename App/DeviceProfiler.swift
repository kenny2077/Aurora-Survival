import Foundation
import os

struct DeviceProfiler {
    func snapshot() -> DeviceSnapshot {
        let thermal: ThermalCondition
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = .nominal
        case .fair: thermal = .fair
        case .serious: thermal = .serious
        case .critical: thermal = .critical
        @unknown default: thermal = .serious
        }

        let values = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let freeStorage = values?.volumeAvailableCapacityForImportantUsage ?? 0

        return DeviceSnapshot(
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            availableMemoryBytes: UInt64(os_proc_available_memory()),
            freeStorageBytes: freeStorage,
            thermalCondition: thermal,
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }
}
