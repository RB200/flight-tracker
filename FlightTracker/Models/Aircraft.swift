import CoreLocation
import Foundation

struct Aircraft: Identifiable, Hashable, Sendable {
    let id: String
    let icao24: String

    var callsign: String?
    var originCountry: String?
    var coordinate: CLLocationCoordinate2D
    var barometricAltitudeMeters: Double?
    var geometricAltitudeMeters: Double?
    var groundSpeedMetersPerSecond: Double?
    var headingDegrees: Double?
    var verticalRateMetersPerSecond: Double?
    var squawk: String?
    var isOnGround: Bool
    var lastContact: Date
    var positionTimestamp: Date?
    var dataSource: String
    var freshness: AircraftFreshness = .fresh
    var flightNumber: String? = nil
    var registration: String? = nil
    var manufacturer: String? = nil
    var model: String? = nil
    var aircraftType: AircraftType = .unknown
    var operatorName: String? = nil
    var airline: Airline? = nil
    var hexCode: String? = nil
    var wakeCategory: WakeCategory = .unknown
    var engineCount: Int? = nil
    var engineType: EngineType = .unknown

    static func == (lhs: Aircraft, rhs: Aircraft) -> Bool {
        lhs.id == rhs.id
            && lhs.icao24 == rhs.icao24
            && lhs.callsign == rhs.callsign
            && lhs.originCountry == rhs.originCountry
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.barometricAltitudeMeters == rhs.barometricAltitudeMeters
            && lhs.geometricAltitudeMeters == rhs.geometricAltitudeMeters
            && lhs.groundSpeedMetersPerSecond == rhs.groundSpeedMetersPerSecond
            && lhs.headingDegrees == rhs.headingDegrees
            && lhs.verticalRateMetersPerSecond == rhs.verticalRateMetersPerSecond
            && lhs.squawk == rhs.squawk
            && lhs.isOnGround == rhs.isOnGround
            && lhs.lastContact == rhs.lastContact
            && lhs.positionTimestamp == rhs.positionTimestamp
            && lhs.dataSource == rhs.dataSource
            && lhs.freshness == rhs.freshness
            && lhs.flightNumber == rhs.flightNumber
            && lhs.registration == rhs.registration
            && lhs.manufacturer == rhs.manufacturer
            && lhs.model == rhs.model
            && lhs.aircraftType == rhs.aircraftType
            && lhs.operatorName == rhs.operatorName
            && lhs.airline == rhs.airline
            && lhs.hexCode == rhs.hexCode
            && lhs.wakeCategory == rhs.wakeCategory
            && lhs.engineCount == rhs.engineCount
            && lhs.engineType == rhs.engineType
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(icao24)
        hasher.combine(coordinate.latitude)
        hasher.combine(coordinate.longitude)
        hasher.combine(lastContact)
    }

    var isStale: Bool {
        freshness != .fresh
    }

    func freshness(
        at date: Date,
        staleThreshold: Duration,
        removalThreshold: Duration
    ) -> AircraftFreshness {
        let age = date.timeIntervalSince(lastContact)
        if age >= removalThreshold.timeInterval { return .expired }
        if age >= staleThreshold.timeInterval { return .stale }
        return .fresh
    }
}

enum AircraftType: String, Codable, CaseIterable, Hashable, Sendable {
    case jet
    case turboprop
    case helicopter
    case glider
    case groundVehicle
    case piston
    case unknown

    var title: String {
        switch self {
        case .jet: "Jet"
        case .turboprop: "Turboprop"
        case .helicopter: "Helicopter"
        case .glider: "Glider"
        case .groundVehicle: "Ground vehicle"
        case .piston: "Piston"
        case .unknown: "Unknown"
        }
    }

    var systemImage: String {
        switch self {
        case .helicopter: "fanblades"
        case .glider: "paperplane.fill"
        case .groundVehicle: "car.fill"
        case .turboprop, .piston: "airplane"
        case .jet, .unknown: "airplane"
        }
    }
}

enum WakeCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case light
    case medium
    case heavy
    case superHeavy
    case unknown

    var title: String {
        switch self {
        case .light: "Light"
        case .medium: "Medium"
        case .heavy: "Heavy"
        case .superHeavy: "Super"
        case .unknown: "Unknown"
        }
    }
}

enum EngineType: String, Codable, CaseIterable, Hashable, Sendable {
    case jet
    case turboprop
    case piston
    case electric
    case none
    case unknown

    var title: String { rawValue.capitalized }
}

struct AircraftSnapshot: Sendable, Equatable {
    let aircraft: [Aircraft]
    let fetchTimestamp: Date
    let providerName: String
    let isStale: Bool
    let isPartial: Bool

    func markedStale() -> AircraftSnapshot {
        AircraftSnapshot(
            aircraft: aircraft,
            fetchTimestamp: fetchTimestamp,
            providerName: providerName,
            isStale: true,
            isPartial: isPartial
        )
    }
}

struct AircraftTrack: Sendable {
    let icao24: String
    let coordinates: [CLLocationCoordinate2D]
}
