import XCTest
@testable import FlightTracker

final class DependencyInjectionTests: XCTestCase {
    func testEnvironmentOwnsInjectedProviderAndPollingServiceUsesIt() async throws {
        let provider = InjectedProvider()
        let environment = AppEnvironment(aircraftProvider: provider)

        XCTAssertTrue(environment.aircraftProvider is InjectedProvider)
        let snapshot = try await environment.aircraftPollingService.fetchSnapshot(in: .continentalUnitedStates)
        XCTAssertEqual(snapshot.providerName, "Injected Test Provider")
    }
}

private struct InjectedProvider: AircraftProvider {
    func fetchAircraft(in bounds: MapBounds) async throws -> AircraftSnapshot {
        AircraftSnapshot(
            aircraft: [],
            fetchTimestamp: Date(),
            providerName: "Injected Test Provider",
            isStale: false,
            isPartial: false
        )
    }

    func fetchAircraft(icao24: String) async throws -> Aircraft? { nil }

    func fetchTrack(icao24: String) async throws -> AircraftTrack {
        AircraftTrack(icao24: icao24, coordinates: [])
    }
}
