import Foundation

public enum OBDService: UInt8, Codable, Sendable {
    case currentData = 0x01
    case freezeFrame = 0x02
    case storedDiagnosticTroubleCodes = 0x03
    case pendingDiagnosticTroubleCodes = 0x07
    case permanentDiagnosticTroubleCodes = 0x0A
}

public enum OBDReadCommand: Hashable, Sendable {
    case resetAdapter
    case echoOff
    case linefeedsOff
    case spacesOff
    case headersOff
    case automaticProtocol
    case describeProtocol
    case supportedPIDs
    case monitorStatus
    case engineCoolantTemperature
    case engineRPM
    case vehicleSpeed
    case intakeAirTemperature
    case throttlePosition
    case storedDTCs
    case pendingDTCs
    case permanentDTCs
    case freezeFrame(pid: UInt8)

    public var wireValue: String {
        switch self {
        case .resetAdapter: return "ATZ"
        case .echoOff: return "ATE0"
        case .linefeedsOff: return "ATL0"
        case .spacesOff: return "ATS0"
        case .headersOff: return "ATH0"
        case .automaticProtocol: return "ATSP0"
        case .describeProtocol: return "ATDP"
        case .supportedPIDs: return "0100"
        case .monitorStatus: return "0101"
        case .engineCoolantTemperature: return "0105"
        case .engineRPM: return "010C"
        case .vehicleSpeed: return "010D"
        case .intakeAirTemperature: return "010F"
        case .throttlePosition: return "0111"
        case .storedDTCs: return "03"
        case .pendingDTCs: return "07"
        case .permanentDTCs: return "0A"
        case .freezeFrame(let pid): return String(format: "02%02X00", pid)
        }
    }
}

public enum OBDPolicyError: Error, Equatable {
    case emptyCommand
    case commandNotAllowed(String)
}

public struct OBDCommandPolicy: Sendable {
    private static let exactAllowed: Set<String> = Set(
        [
            OBDReadCommand.resetAdapter,
            .echoOff,
            .linefeedsOff,
            .spacesOff,
            .headersOff,
            .automaticProtocol,
            .describeProtocol,
            .supportedPIDs,
            .monitorStatus,
            .engineCoolantTemperature,
            .engineRPM,
            .vehicleSpeed,
            .intakeAirTemperature,
            .throttlePosition,
            .storedDTCs,
            .pendingDTCs,
            .permanentDTCs
        ].map(\.wireValue)
    )

    public init() {}

    public func validate(_ command: String) throws -> String {
        let normalized = command
            .uppercased()
            .filter { !$0.isWhitespace && $0 != "\r" && $0 != "\n" }
        guard !normalized.isEmpty else { throw OBDPolicyError.emptyCommand }
        if Self.exactAllowed.contains(normalized) {
            return normalized
        }
        if normalized.count == 6,
           normalized.hasPrefix("02"),
           normalized.suffix(2) == "00",
           normalized.dropFirst(2).prefix(2).allSatisfy(\.isHexDigit) {
            return normalized
        }
        throw OBDPolicyError.commandNotAllowed(normalized)
    }
}

public struct DiagnosticTroubleCode: Codable, Hashable, Sendable, Identifiable {
    public var id: String { code }
    public let code: String

    public init(code: String) {
        self.code = code
    }
}

public enum OBDParseError: Error, Equatable {
    case noData
    case malformedResponse
    case negativeResponse(code: UInt8)
}

public struct ELM327Parser: Sendable {
    public init() {}

    public func dataBytes(from response: String, expectedService: UInt8) throws -> [UInt8] {
        let cleanedLines = response
            .uppercased()
            .replacingOccurrences(of: "SEARCHING...", with: "")
            .replacingOccurrences(of: ">", with: "")
            .split(whereSeparator: \.isNewline)
            .map {
                $0.filter { $0.isHexDigit || $0.isWhitespace }
                    .split(whereSeparator: \.isWhitespace)
                    .joined()
            }
            .filter { !$0.isEmpty }

        if response.uppercased().contains("NO DATA") {
            throw OBDParseError.noData
        }

        for line in cleanedLines {
            let bytes = stride(from: 0, to: line.count - (line.count % 2), by: 2)
                .compactMap { offset -> UInt8? in
                    let start = line.index(line.startIndex, offsetBy: offset)
                    let end = line.index(start, offsetBy: 2)
                    return UInt8(line[start..<end], radix: 16)
                }
            guard let service = bytes.first else { continue }
            if service == 0x7F, bytes.count >= 3 {
                throw OBDParseError.negativeResponse(code: bytes[2])
            }
            if service == expectedService {
                return Array(bytes.dropFirst())
            }
        }
        throw OBDParseError.malformedResponse
    }

    public func diagnosticTroubleCodes(
        from response: String,
        requestService: OBDService = .storedDiagnosticTroubleCodes
    ) throws -> [DiagnosticTroubleCode] {
        let responseService = requestService.rawValue + 0x40
        let bytes = try dataBytes(from: response, expectedService: responseService)
        var result: [DiagnosticTroubleCode] = []
        for index in stride(from: 0, to: bytes.count - 1, by: 2) {
            let first = bytes[index]
            let second = bytes[index + 1]
            if first == 0 && second == 0 { continue }

            let family = ["P", "C", "B", "U"][Int(first >> 6)]
            let digit = (first >> 4) & 0x03
            let code = String(
                format: "%@%01X%01X%01X%01X",
                family,
                digit,
                first & 0x0F,
                second >> 4,
                second & 0x0F
            )
            result.append(DiagnosticTroubleCode(code: code))
        }
        return result
    }

    public func scalarValue(
        from response: String,
        pid: UInt8
    ) throws -> Double {
        let bytes = try dataBytes(from: response, expectedService: 0x41)
        guard bytes.first == pid, bytes.count >= 2 else {
            throw OBDParseError.malformedResponse
        }
        let a = Double(bytes[1])
        switch pid {
        case 0x05, 0x0F: return a - 40
        case 0x0C:
            guard bytes.count >= 3 else { throw OBDParseError.malformedResponse }
            return ((a * 256) + Double(bytes[2])) / 4
        case 0x0D: return a
        case 0x11: return a * 100 / 255
        default: throw OBDParseError.malformedResponse
        }
    }
}

public protocol OBDTransport: Sendable {
    func exchange(command: String) async throws -> String
}

public actor ReadOnlyOBDSession {
    private let transport: any OBDTransport
    private let policy: OBDCommandPolicy

    public init(
        transport: any OBDTransport,
        policy: OBDCommandPolicy = OBDCommandPolicy()
    ) {
        self.transport = transport
        self.policy = policy
    }

    public func execute(_ command: OBDReadCommand) async throws -> String {
        let approved = try policy.validate(command.wireValue)
        return try await transport.exchange(command: approved + "\r")
    }

    public func executeRaw(_ command: String) async throws -> String {
        let approved = try policy.validate(command)
        return try await transport.exchange(command: approved + "\r")
    }
}
