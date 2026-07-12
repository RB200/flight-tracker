import CoreLocation
import Foundation

struct OpenSkyStateResponse: Decodable, Sendable {
    let time: Int
    private let states: [[OpenSkyJSONValue]]?

    var stateVectors: [OpenSkyStateVector] {
        states?.compactMap(OpenSkyStateVector.init(row:)) ?? []
    }

    func normalizedAircraft(providerName: String) -> [Aircraft] {
        let fallbackDate = Date(timeIntervalSince1970: TimeInterval(time))
        return stateVectors.map { $0.normalizedAircraft(providerName: providerName, fallbackDate: fallbackDate) }
    }
}

struct OpenSkyStateVector: Sendable, Equatable {
    let icao24: String
    let callsign: String?
    let originCountry: String?
    let positionTimestamp: TimeInterval?
    let lastContact: TimeInterval?
    let longitude: Double
    let latitude: Double
    let barometricAltitudeMeters: Double?
    let isOnGround: Bool
    let groundSpeedMetersPerSecond: Double?
    let headingDegrees: Double?
    let verticalRateMetersPerSecond: Double?
    let geometricAltitudeMeters: Double?
    let squawk: String?

    // OpenSky's heterogeneous state-vector array schema is indexed only here.
    init?(row: [OpenSkyJSONValue]) {
        guard
            let rawICAO24 = row[safe: 0]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
            !rawICAO24.isEmpty,
            let longitude = row[safe: 5]?.doubleValue,
            let latitude = row[safe: 6]?.doubleValue,
            (-180...180).contains(longitude),
            (-90...90).contains(latitude)
        else {
            return nil
        }

        icao24 = rawICAO24.lowercased()
        callsign = Self.trimmed(row[safe: 1]?.stringValue)
        originCountry = Self.trimmed(row[safe: 2]?.stringValue)
        positionTimestamp = row[safe: 3]?.doubleValue
        lastContact = row[safe: 4]?.doubleValue
        self.longitude = longitude
        self.latitude = latitude
        barometricAltitudeMeters = row[safe: 7]?.doubleValue
        isOnGround = row[safe: 8]?.boolValue ?? false
        groundSpeedMetersPerSecond = row[safe: 9]?.doubleValue
        headingDegrees = row[safe: 10]?.doubleValue.map { $0.truncatingRemainder(dividingBy: 360) }
        verticalRateMetersPerSecond = row[safe: 11]?.doubleValue
        geometricAltitudeMeters = row[safe: 13]?.doubleValue
        squawk = Self.trimmed(row[safe: 14]?.stringValue)
    }

    func normalizedAircraft(providerName: String, fallbackDate: Date) -> Aircraft {
        Aircraft(
            id: icao24,
            icao24: icao24,
            callsign: callsign,
            originCountry: originCountry,
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            barometricAltitudeMeters: barometricAltitudeMeters,
            geometricAltitudeMeters: geometricAltitudeMeters,
            groundSpeedMetersPerSecond: groundSpeedMetersPerSecond,
            headingDegrees: headingDegrees,
            verticalRateMetersPerSecond: verticalRateMetersPerSecond,
            squawk: squawk,
            isOnGround: isOnGround,
            lastContact: lastContact.map(Date.init(timeIntervalSince1970:)) ?? fallbackDate,
            positionTimestamp: positionTimestamp.map(Date.init(timeIntervalSince1970:)),
            dataSource: providerName,
            flightNumber: callsign,
            airline: callsign.flatMap { value in Airline.byICAO[String(value.prefix(3)).uppercased()] },
            hexCode: icao24
        )
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

struct OpenSkyTrackResponse: Decodable, Sendable {
    let icao24: String
    let startTime: Int
    let endTime: Int
    let calllsign: String?
    private let path: [[OpenSkyJSONValue]]

    var waypoints: [OpenSkyTrackWaypoint] {
        path.compactMap(OpenSkyTrackWaypoint.init(row:))
    }
}

struct OpenSkyTrackWaypoint: Sendable, Equatable {
    let timestamp: TimeInterval
    let coordinate: CLLocationCoordinate2D
    let barometricAltitudeMeters: Double?
    let headingDegrees: Double?
    let isOnGround: Bool

    // OpenSky's heterogeneous track-waypoint array schema is indexed only here.
    init?(row: [OpenSkyJSONValue]) {
        guard
            let timestamp = row[safe: 0]?.doubleValue,
            let latitude = row[safe: 1]?.doubleValue,
            let longitude = row[safe: 2]?.doubleValue,
            (-90...90).contains(latitude),
            (-180...180).contains(longitude)
        else {
            return nil
        }
        self.timestamp = timestamp
        coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        barometricAltitudeMeters = row[safe: 3]?.doubleValue
        headingDegrees = row[safe: 4]?.doubleValue
        isOnGround = row[safe: 5]?.boolValue ?? false
    }

    static func == (lhs: OpenSkyTrackWaypoint, rhs: OpenSkyTrackWaypoint) -> Bool {
        lhs.timestamp == rhs.timestamp
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.barometricAltitudeMeters == rhs.barometricAltitudeMeters
            && lhs.headingDegrees == rhs.headingDegrees
            && lhs.isOnGround == rhs.isOnGround
    }
}

enum OpenSkyJSONValue: Decodable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([OpenSkyJSONValue])
    case object([String: OpenSkyJSONValue])
    case null

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([OpenSkyJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: OpenSkyJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported OpenSky JSON value")
        }
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var doubleValue: Double? {
        guard case .number(let value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
