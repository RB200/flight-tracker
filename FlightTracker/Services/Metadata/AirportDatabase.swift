import CoreLocation
import Foundation

actor AirportDatabase {
    enum State: Sendable, Equatable { case unloaded, loading, loaded(Int), failed(String) }

    private let resourceURL: URL?
    private var airportsByID: [String: Airport] = [:]
    private var airportIDByCode: [String: String] = [:]
    private var spatialBuckets: [Bucket: [String]] = [:]
    private(set) var state: State = .unloaded

    init(resourceURL: URL? = Bundle.main.url(forResource: "Airports", withExtension: "json")) {
        self.resourceURL = resourceURL
    }

    func load() async throws -> [Airport] {
        if !airportsByID.isEmpty { return Array(airportsByID.values) }
        guard state != .loading else {
            while state == .loading { try await Task.sleep(for: .milliseconds(20)) }
            return Array(airportsByID.values)
        }
        state = .loading
        do {
            guard let resourceURL else { throw AirportDatabaseError.resourceMissing }
            let data = try Data(contentsOf: resourceURL, options: [.mappedIfSafe])
            try Task.checkCancellation()
            let decoded = try JSONDecoder().decode([Airport].self, from: data)
            airportsByID = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
            airportIDByCode = decoded.reduce(into: [:]) { result, airport in
                for code in [airport.id, airport.icao, airport.iata].compactMap({ $0 }) {
                    result[code.uppercased()] = airport.id
                }
            }
            spatialBuckets = Dictionary(grouping: decoded, by: { Bucket(coordinate: $0.coordinate) })
                .mapValues { $0.map(\.id) }
            state = .loaded(decoded.count)
            return decoded
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    func airport(id: String) -> Airport? { airportsByID[id.uppercased()] }

    func airport(code: String) async -> Airport? {
        if airportsByID.isEmpty { _ = try? await load() }
        let code = code.uppercased()
        return airportIDByCode[code].flatMap { airportsByID[$0] }
    }

    func airports(in bounds: MapBounds, limit: Int = 1_500) -> [Airport] {
        guard !airportsByID.isEmpty else { return [] }
        let minimumLatitudeCell = Int(floor((bounds.minimumLatitude + 90) / Bucket.size))
        let maximumLatitudeCell = Int(floor((bounds.maximumLatitude + 90) / Bucket.size))
        let longitudeRanges = bounds.splitAtAntimeridian().map {
            Int(floor(($0.minimumLongitude + 180) / Bucket.size))...Int(floor(($0.maximumLongitude + 180) / Bucket.size))
        }
        var ids = Set<String>()
        for latitudeCell in minimumLatitudeCell...maximumLatitudeCell {
            for range in longitudeRanges {
                for longitudeCell in range {
                    ids.formUnion(spatialBuckets[Bucket(latitude: latitudeCell, longitude: longitudeCell)] ?? [])
                }
            }
        }
        return ids.compactMap { airportsByID[$0] }
            .filter { bounds.contains($0.coordinate) }
            .sorted { lhs, rhs in
                let lp = Self.priority(lhs.type), rp = Self.priority(rhs.type)
                return lp == rp ? lhs.name < rhs.name : lp < rp
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func priority(_ type: AirportType) -> Int {
        switch type { case .large: 0; case .medium: 1; case .small: 2; case .heliport: 3; case .seaplaneBase: 4 }
    }
}

private struct Bucket: Hashable, Sendable {
    static let size = 5.0
    let latitude: Int
    let longitude: Int

    init(latitude: Int, longitude: Int) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(coordinate: CLLocationCoordinate2D) {
        latitude = Int(floor((coordinate.latitude + 90) / Self.size))
        longitude = Int(floor((coordinate.longitude + 180) / Self.size))
    }
}

enum AirportDatabaseError: LocalizedError {
    case resourceMissing
    var errorDescription: String? { "The bundled airport database is unavailable." }
}
