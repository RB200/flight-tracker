import Foundation

protocol AircraftProvider: Sendable {
    func fetchAircraft(in bounds: MapBounds) async throws -> AircraftSnapshot
    func fetchAircraft(icao24: String) async throws -> Aircraft?
    func fetchTrack(icao24: String) async throws -> AircraftTrack
}

enum AircraftProviderError: LocalizedError {
    case aircraftNotFound
    case trackUnavailable

    var errorDescription: String? {
        switch self {
        case .aircraftNotFound:
            "Aircraft not found."
        case .trackUnavailable:
            "Track history is not available in the static mock."
        }
    }
}
