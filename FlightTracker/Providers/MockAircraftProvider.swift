import CoreLocation
import Foundation
import OSLog

actor MockAircraftProvider: AircraftProvider {
    private let seed: UInt64
    private let aircraftCount: Int
    private let failureAfterRequestCount: Int?
    private let responseDelay: Duration?
    private var world: [String: Aircraft] = [:]
    private var requestCount = 0
    private let logger = Logger(subsystem: "com.example.FlightTracker", category: "MockProvider")

    init(
        seed: UInt64 = 0xF1A6_2026,
        aircraftCount: Int = 500,
        failureAfterRequestCount: Int? = nil,
        responseDelay: Duration? = nil
    ) {
        self.seed = seed
        self.aircraftCount = aircraftCount
        self.failureAfterRequestCount = failureAfterRequestCount
        self.responseDelay = responseDelay
    }

    func fetchAircraft(in bounds: MapBounds) async throws -> AircraftSnapshot {
        try Task.checkCancellation()
        if let responseDelay { try await Task.sleep(for: responseDelay) }
        requestCount += 1
        if let failureAfterRequestCount, requestCount > failureAfterRequestCount {
            logger.warning("Simulating offline provider after request \(self.requestCount)")
            throw APIError.offline
        }

        let now = Date()
        if world.isEmpty {
            world = generateWorld(in: bounds, now: now)
        } else {
            moveWorld(now: now)
        }
        let visible = world.values.filter { bounds.contains($0.coordinate) }.sorted { $0.icao24 < $1.icao24 }
        return AircraftSnapshot(
            aircraft: visible,
            fetchTimestamp: now,
            providerName: "Seeded Mock ADS-B",
            isStale: false,
            isPartial: false
        )
    }

    func fetchAircraft(icao24: String) async throws -> Aircraft? {
        if world.isEmpty {
            _ = try await fetchAircraft(in: .continentalUnitedStates)
        }
        return world[icao24.uppercased()]
    }

    func fetchTrack(icao24: String) async throws -> AircraftTrack {
        throw AircraftProviderError.trackUnavailable
    }

    private func generateWorld(in bounds: MapBounds, now: Date) -> [String: Aircraft] {
        var generator = SeededGenerator(seed: seed)
        let countries = ["United States", "Canada", "Mexico", "United Kingdom", "Germany", "France"]
        let prefixes = ["AAL", "DAL", "UAL", "SWA", "JBU", "ASA", "FFT", "NKS"]
        return Dictionary(uniqueKeysWithValues: (0..<aircraftCount).map { index in
            let latitude = generator.value(in: bounds.minimumLatitude...bounds.maximumLatitude)
            let longitudeOffset = generator.value(in: 0...bounds.longitudeSpan)
            let longitude = MapBounds.normalizeLongitude(bounds.minimumLongitude + longitudeOffset)
            let onGround = index % 29 == 0
            let altitude = onGround ? generator.value(in: 0...150) : generator.value(in: 1_200...12_200)
            let speed = onGround ? generator.value(in: 0...18) : generator.value(in: 80...275)
            let icao24 = String(format: "%06X", 0xA00000 + index)
            let airline = Airline.byICAO[prefixes[index % prefixes.count]]
            let type: AircraftType = index % 47 == 0 ? .helicopter : (index % 11 == 0 ? .turboprop : .jet)
            let manufacturer = type == .turboprop ? "De Havilland Canada" : (type == .helicopter ? "Airbus Helicopters" : (index.isMultiple(of: 2) ? "Boeing" : "Airbus"))
            let model = type == .turboprop ? "Dash 8-400" : (type == .helicopter ? "H145" : (index.isMultiple(of: 2) ? "737-800" : "A320-200"))
            let stale = index % 41 == 0
            let contact = now.addingTimeInterval(stale ? -45 : -Double(index % 10))
            let aircraft = Aircraft(
                id: icao24,
                icao24: icao24,
                callsign: "\(prefixes[index % prefixes.count])\(100 + (index * 37) % 9_800)",
                originCountry: countries[index % countries.count],
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                barometricAltitudeMeters: altitude,
                geometricAltitudeMeters: altitude + generator.value(in: -90...140),
                groundSpeedMetersPerSecond: speed,
                headingDegrees: generator.value(in: 0..<360),
                verticalRateMetersPerSecond: onGround ? 0 : generator.value(in: -12...12),
                squawk: String(format: "%04d", 1000 + (index * 13) % 6777),
                isOnGround: onGround,
                lastContact: contact,
                positionTimestamp: contact,
                dataSource: "Seeded Mock ADS-B",
                freshness: stale ? .stale : .fresh,
                flightNumber: "\(airline?.iata ?? prefixes[index % prefixes.count]) \(100 + (index * 37) % 9_800)",
                registration: "N\(10000 + index)",
                manufacturer: manufacturer,
                model: model,
                aircraftType: onGround && index % 58 == 0 ? .groundVehicle : type,
                operatorName: airline?.name,
                airline: airline,
                hexCode: icao24,
                wakeCategory: type == .helicopter ? .light : (index % 13 == 0 ? .heavy : .medium),
                engineCount: type == .helicopter ? 1 : 2,
                engineType: type == .turboprop ? .turboprop : .jet
            )
            return (icao24, aircraft)
        })
    }

    private func moveWorld(now: Date) {
        for key in world.keys.sorted() {
            guard var aircraft = world[key], aircraft.freshness == .fresh, !aircraft.isOnGround else { continue }
            let heading = (aircraft.headingDegrees ?? 0) * .pi / 180
            let distance = (aircraft.groundSpeedMetersPerSecond ?? 0) * 10
            var latitude = aircraft.coordinate.latitude + (distance * cos(heading)) / 111_320
            if latitude > 89 || latitude < -89 {
                latitude = min(max(latitude, -89), 89)
                aircraft.headingDegrees = (360 - (aircraft.headingDegrees ?? 0)).truncatingRemainder(dividingBy: 360)
            }
            let longitudeScale = max(0.01, cos(latitude * .pi / 180))
            let longitude = aircraft.coordinate.longitude + (distance * sin(heading)) / (111_320 * longitudeScale)
            aircraft.coordinate = CLLocationCoordinate2D(
                latitude: latitude,
                longitude: MapBounds.normalizeLongitude(longitude)
            )
            aircraft.lastContact = now
            aircraft.positionTimestamp = now
            world[key] = aircraft
        }
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    mutating func value(in range: ClosedRange<Double>) -> Double {
        Double.random(in: range, using: &self)
    }

    mutating func value(in range: Range<Double>) -> Double {
        Double.random(in: range, using: &self)
    }
}
