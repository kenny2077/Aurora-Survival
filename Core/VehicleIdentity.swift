import Foundation

public enum VehiclePowertrain: String, Codable, CaseIterable, Sendable {
    case gasoline
    case diesel
    case hybrid
    case plugInHybrid = "plug_in_hybrid"
    case batteryElectric = "battery_electric"
    case other

    public var displayName: String {
        switch self {
        case .gasoline: return "Gasoline"
        case .diesel: return "Diesel"
        case .hybrid: return "Hybrid"
        case .plugInHybrid: return "Plug-in hybrid"
        case .batteryElectric: return "Battery electric"
        case .other: return "Other"
        }
    }
}

public struct VehicleProfile: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let make: String
    public let model: String
    public let modelYear: Int
    public let market: String
    public let powertrain: VehiclePowertrain
    public let documentID: String?
    public let vinLastSix: String?

    public init(
        id: UUID = UUID(),
        make: String,
        model: String,
        modelYear: Int,
        market: String,
        powertrain: VehiclePowertrain,
        documentID: String? = nil,
        vinLastSix: String? = nil
    ) {
        self.id = id
        self.make = Self.normalize(make)
        self.model = Self.normalize(model)
        self.modelYear = modelYear
        self.market = Self.normalize(market)
        self.powertrain = powertrain
        self.documentID = documentID.map(Self.normalize)
        self.vinLastSix = vinLastSix.map { String($0.uppercased().suffix(6)) }
    }

    public var displayName: String {
        "\(modelYear) \(make) \(model)"
    }

    public var isPlausible: Bool {
        let nextModelYear = Calendar(identifier: .gregorian)
            .component(.year, from: Date()) + 2
        return (1886...nextModelYear).contains(modelYear)
            && !make.isEmpty
            && !model.isEmpty
            && !market.isEmpty
    }

    static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

public struct VehicleApplicability: Codable, Hashable, Sendable {
    public let makes: [String]
    public let models: [String]
    public let yearFrom: Int
    public let yearThrough: Int
    public let markets: [String]
    public let powertrains: [VehiclePowertrain]
    public let documentIDs: [String]

    public init(
        makes: [String],
        models: [String],
        yearFrom: Int,
        yearThrough: Int,
        markets: [String] = [],
        powertrains: [VehiclePowertrain] = [],
        documentIDs: [String] = []
    ) {
        self.makes = makes.map(VehicleProfile.normalize)
        self.models = models.map(VehicleProfile.normalize)
        self.yearFrom = yearFrom
        self.yearThrough = yearThrough
        self.markets = markets.map(VehicleProfile.normalize)
        self.powertrains = powertrains
        self.documentIDs = documentIDs.map(VehicleProfile.normalize)
    }

    public func matches(_ vehicle: VehicleProfile) -> Bool {
        guard vehicle.isPlausible,
              yearFrom <= vehicle.modelYear,
              vehicle.modelYear <= yearThrough,
              Self.contains(makes, value: vehicle.make),
              Self.contains(models, value: vehicle.model)
        else { return false }

        if !markets.isEmpty && !Self.contains(markets, value: vehicle.market) {
            return false
        }
        if !powertrains.isEmpty && !powertrains.contains(vehicle.powertrain) {
            return false
        }
        if !documentIDs.isEmpty {
            guard let documentID = vehicle.documentID,
                  Self.contains(documentIDs, value: documentID)
            else { return false }
        }
        return true
    }

    private static func contains(_ candidates: [String], value: String) -> Bool {
        guard !candidates.isEmpty else { return true }
        return candidates.contains {
            $0.compare(value, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }
}
