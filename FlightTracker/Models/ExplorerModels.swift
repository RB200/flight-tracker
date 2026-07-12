import CoreLocation
import Foundation

struct Airline: Identifiable, Codable, Hashable, Sendable {
    var id: String { icao }
    let icao: String
    let iata: String?
    let name: String
    let country: String
    let callsign: String?

    static let builtIn: [Airline] = [
        Airline(icao: "AAL", iata: "AA", name: "American Airlines", country: "United States", callsign: "AMERICAN"),
        Airline(icao: "ASA", iata: "AS", name: "Alaska Airlines", country: "United States", callsign: "ALASKA"),
        Airline(icao: "DAL", iata: "DL", name: "Delta Air Lines", country: "United States", callsign: "DELTA"),
        Airline(icao: "FFT", iata: "F9", name: "Frontier Airlines", country: "United States", callsign: "FRONTIER FLIGHT"),
        Airline(icao: "JBU", iata: "B6", name: "JetBlue Airways", country: "United States", callsign: "JETBLUE"),
        Airline(icao: "NKS", iata: "NK", name: "Spirit Airlines", country: "United States", callsign: "SPIRIT WINGS"),
        Airline(icao: "SWA", iata: "WN", name: "Southwest Airlines", country: "United States", callsign: "SOUTHWEST"),
        Airline(icao: "UAL", iata: "UA", name: "United Airlines", country: "United States", callsign: "UNITED")
    ]

    static let byICAO = Dictionary(uniqueKeysWithValues: builtIn.map { ($0.icao, $0) })
}

struct AirportRunway: Codable, Hashable, Sendable {
    let name: String
    let lengthFeet: Int
    let surface: String?
}

enum AirportType: String, Codable, Hashable, Sendable {
    case large = "large_airport"
    case medium = "medium_airport"
    case small = "small_airport"
    case heliport
    case seaplaneBase = "seaplane_base"
}

struct Airport: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let icao: String
    let iata: String?
    let name: String
    let latitude: Double
    let longitude: Double
    let elevationFeet: Int?
    let country: String
    let city: String?
    let timezone: String
    let type: AirportType
    let runways: [AirportRunway]

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var displayCode: String { iata ?? icao }
}

enum FavoriteID: Hashable, Sendable {
    case aircraft(String)
    case airport(String)
    case airline(String)
}

enum ExplorerSearchResult: Identifiable, Hashable, Sendable {
    case aircraft(Aircraft)
    case airport(Airport)
    case airline(Airline)

    var id: String {
        switch self {
        case .aircraft(let aircraft): "aircraft:\(aircraft.icao24)"
        case .airport(let airport): "airport:\(airport.id)"
        case .airline(let airline): "airline:\(airline.icao)"
        }
    }

    var title: String {
        switch self {
        case .aircraft(let aircraft): aircraft.callsign ?? aircraft.registration ?? aircraft.icao24.uppercased()
        case .airport(let airport): airport.name
        case .airline(let airline): airline.name
        }
    }

    var subtitle: String {
        switch self {
        case .aircraft(let aircraft): [aircraft.flightNumber, aircraft.registration, aircraft.icao24.uppercased()].compactMap { $0 }.joined(separator: " · ")
        case .airport(let airport): [airport.iata, airport.icao, airport.city, airport.country].compactMap { $0 }.joined(separator: " · ")
        case .airline(let airline): [airline.iata, airline.icao, airline.country].compactMap { $0 }.joined(separator: " · ")
        }
    }

    var systemImage: String {
        switch self {
        case .aircraft(let aircraft): aircraft.aircraftType.systemImage
        case .airport: "building.2.fill"
        case .airline: "airplane.circle.fill"
        }
    }

    var favoriteID: FavoriteID {
        switch self {
        case .aircraft(let aircraft): .aircraft(aircraft.icao24)
        case .airport(let airport): .airport(airport.id)
        case .airline(let airline): .airline(airline.icao)
        }
    }
}

struct AircraftFilter: Equatable, Sendable {
    var minimumAltitudeFeet: Double?
    var maximumAltitudeFeet: Double?
    var minimumSpeedKnots: Double?
    var maximumSpeedKnots: Double?
    var aircraftTypes: Set<AircraftType> = []
    var airlineICAOs: Set<String> = []
    var countries: Set<String> = []
    var airborne: Bool?
    var freshness: AircraftFreshness?
    var wakeCategories: Set<WakeCategory> = []
    var engineTypes: Set<EngineType> = []
    var operators: Set<String> = []

    var isActive: Bool {
        minimumAltitudeFeet != nil || maximumAltitudeFeet != nil
            || minimumSpeedKnots != nil || maximumSpeedKnots != nil
            || !aircraftTypes.isEmpty || !airlineICAOs.isEmpty || !countries.isEmpty
            || airborne != nil || freshness != nil || !wakeCategories.isEmpty
            || !engineTypes.isEmpty || !operators.isEmpty
    }

    func includes(_ aircraft: Aircraft) -> Bool {
        let altitude = aircraft.barometricAltitudeMeters.map { $0 * 3.28084 }
        let speed = aircraft.groundSpeedMetersPerSecond.map { $0 * 1.94384 }
        if let minimumAltitudeFeet, (altitude ?? -.infinity) < minimumAltitudeFeet { return false }
        if let maximumAltitudeFeet, (altitude ?? .infinity) > maximumAltitudeFeet { return false }
        if let minimumSpeedKnots, (speed ?? -.infinity) < minimumSpeedKnots { return false }
        if let maximumSpeedKnots, (speed ?? .infinity) > maximumSpeedKnots { return false }
        if !aircraftTypes.isEmpty, !aircraftTypes.contains(aircraft.aircraftType) { return false }
        if !airlineICAOs.isEmpty, !airlineICAOs.contains(aircraft.airline?.icao ?? "") { return false }
        if !countries.isEmpty, !countries.contains(aircraft.originCountry ?? "") { return false }
        if let airborne, airborne == aircraft.isOnGround { return false }
        if let freshness, aircraft.freshness != freshness { return false }
        if !wakeCategories.isEmpty, !wakeCategories.contains(aircraft.wakeCategory) { return false }
        if !engineTypes.isEmpty, !engineTypes.contains(aircraft.engineType) { return false }
        if !operators.isEmpty, !operators.contains(aircraft.operatorName ?? "") { return false }
        return true
    }
}

struct MapCameraRequest: Equatable, Sendable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let latitudeSpan: Double

    static func == (lhs: MapCameraRequest, rhs: MapCameraRequest) -> Bool { lhs.id == rhs.id }
}

enum ExplorerSheet: String, Identifiable, Sendable {
    case aircraft
    case airport
    case filters

    var id: String { rawValue }
}
