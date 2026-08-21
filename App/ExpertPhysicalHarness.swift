#if DEBUG
import Darwin
import Foundation

struct ExpertPhysicalBenchmarkCase: Codable, Sendable {
    enum RunMode: String, Codable, Sendable {
        case nativeVision = "native_vision"
        case grounded
        case rag
        case multiTurn = "multi_turn"
    }

    struct HistoryTurn: Codable, Sendable {
        let role: String
        let text: String
    }

    let id: String
    let question: String
    let imageFilename: String?
    let runMode: RunMode
    let safetyCritical: Bool
    let domain: KnowledgeDomain?
    let resetSession: Bool
    let expectedLessonIDs: [String]
    let acceptableEvidenceSets: [[String]]?
    let expectedDisposition: ExpertPlanDisposition?
    let expectedRiskClass: ExpertRiskClass?
    let forbiddenClaims: [String]?
    let requiredAnswerTermGroups: [[String]]?
    let history: [HistoryTurn]
    let imageObservations: [String]
}

struct ExpertProcessMemoryResult: Codable, Sendable {
    let peakPhysicalFootprintBytes: UInt64
    let minimumAvailableMemoryBytes: UInt64
}

struct PhysicalBenchmarkStatus: Equatable, Sendable {
    let completedCases: Int
    let totalCases: Int
    let phase: String
    let thermal: ThermalCondition
    let batteryLevel: Float
    let availableMemoryBytes: UInt64?
    let cooldownSecondsRemaining: Int?
}

enum ExpertProcessMemoryProbe {
    static func physicalFootprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size
                / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(
                to: integer_t.self,
                capacity: Int(count)
            ) { rebound in
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    rebound,
                    &count
                )
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
}

actor ExpertProcessMemorySampler {
    private var isRunning = true
    private var peakPhysicalFootprintBytes: UInt64 = 0
    private var minimumAvailableMemoryBytes: UInt64 = .max

    func sampleUntilStopped() async {
        while isRunning {
            capture()
            try? await Task.sleep(for: .milliseconds(100))
        }
        capture()
    }

    func stop() {
        isRunning = false
    }

    func result() -> ExpertProcessMemoryResult {
        ExpertProcessMemoryResult(
            peakPhysicalFootprintBytes: peakPhysicalFootprintBytes,
            minimumAvailableMemoryBytes: minimumAvailableMemoryBytes == .max
                ? 0
                : minimumAvailableMemoryBytes
        )
    }

    private func capture() {
        peakPhysicalFootprintBytes = max(
            peakPhysicalFootprintBytes,
            ExpertProcessMemoryProbe.physicalFootprintBytes()
        )
        minimumAvailableMemoryBytes = min(
            minimumAvailableMemoryBytes,
            UInt64(os_proc_available_memory())
        )
    }
}
#endif
