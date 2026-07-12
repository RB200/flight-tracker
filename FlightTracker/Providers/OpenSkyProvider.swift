import Foundation

struct OpenSkyProvider: AircraftProvider {
    static let providerName = "OpenSky Network"

    private let client: APIClient
    private let baseURL: URL
    private let bearerToken: String?
    private let staleThreshold: TimeInterval

    init(
        client: APIClient = APIClient(),
        baseURL: URL = URL(string: "https://opensky-network.org/api")!,
        bearerToken: String? = nil,
        staleThreshold: TimeInterval = 30
    ) {
        self.client = client
        self.baseURL = baseURL
        self.bearerToken = bearerToken
        self.staleThreshold = staleThreshold
    }

    func fetchAircraft(in bounds: MapBounds) async throws -> AircraftSnapshot {
        let response: OpenSkyStateResponse = try await client.send(
            stateEndpoint(queryItems: [
                URLQueryItem(name: "lamin", value: String(bounds.south)),
                URLQueryItem(name: "lomin", value: String(bounds.west)),
                URLQueryItem(name: "lamax", value: String(bounds.north)),
                URLQueryItem(name: "lomax", value: String(bounds.east))
            ])
        )
        return snapshot(from: response)
    }

    func fetchAircraft(icao24: String) async throws -> Aircraft? {
        let response: OpenSkyStateResponse = try await client.send(
            stateEndpoint(queryItems: [URLQueryItem(name: "icao24", value: icao24.lowercased())])
        )
        return response.normalizedAircraft(providerName: Self.providerName).first
    }

    func fetchTrack(icao24: String) async throws -> AircraftTrack {
        let endpoint = Endpoint<OpenSkyTrackResponse>(
            baseURL: baseURL,
            path: "tracks/all",
            queryItems: [
                URLQueryItem(name: "icao24", value: icao24.lowercased()),
                URLQueryItem(name: "time", value: "0")
            ],
            headers: authorizationHeaders
        )
        let response = try await client.send(endpoint)
        return AircraftTrack(
            icao24: response.icao24.lowercased(),
            coordinates: response.waypoints.map(\.coordinate)
        )
    }

    private func stateEndpoint(queryItems: [URLQueryItem]) -> Endpoint<OpenSkyStateResponse> {
        Endpoint(
            baseURL: baseURL,
            path: "states/all",
            queryItems: queryItems,
            headers: authorizationHeaders
        )
    }

    private func snapshot(from response: OpenSkyStateResponse) -> AircraftSnapshot {
        let now = Date()
        let providerTimestamp = Date(timeIntervalSince1970: TimeInterval(response.time))
        return AircraftSnapshot(
            aircraft: response.normalizedAircraft(providerName: Self.providerName),
            fetchTimestamp: now,
            providerName: Self.providerName,
            isStale: now.timeIntervalSince(providerTimestamp) > staleThreshold,
            isPartial: false
        )
    }

    private var authorizationHeaders: [String: String] {
        guard let bearerToken, !bearerToken.isEmpty else { return [:] }
        return ["Authorization": "Bearer \(bearerToken)"]
    }
}
