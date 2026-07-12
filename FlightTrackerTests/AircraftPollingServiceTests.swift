import XCTest
@testable import FlightTracker

final class AircraftPollingServiceTests: XCTestCase {
    func testServiceRetriesTransientProviderFailure() async throws {
        let provider = FlakyProvider(failuresBeforeSuccess: 1)
        let service = AircraftPollingService(
            provider: provider,
            retryPolicy: PollingRetryPolicy(maximumRetryCount: 1, baseDelay: 0),
            sleeper: RetrySleeper { _ in }
        )

        let snapshot = try await service.fetchSnapshot(in: .continentalUnitedStates)
        let attemptCount = await provider.attemptCount

        XCTAssertEqual(snapshot.providerName, "Flaky Test Provider")
        XCTAssertEqual(attemptCount, 2)
    }

    func testServiceReturnsCachedSnapshotMarkedStaleAfterFailure() async throws {
        let provider = FlakyProvider(failuresBeforeSuccess: 0)
        let service = AircraftPollingService(
            provider: provider,
            retryPolicy: PollingRetryPolicy(maximumRetryCount: 0)
        )
        _ = try await service.fetchSnapshot(in: .continentalUnitedStates)
        await provider.failAllRequests()

        let snapshot = try await service.fetchSnapshot(in: .continentalUnitedStates)

        XCTAssertTrue(snapshot.isStale)
        XCTAssertEqual(snapshot.providerName, "Flaky Test Provider")
    }
}

private actor FlakyProvider: AircraftProvider {
    private let failuresBeforeSuccess: Int
    private var alwaysFail = false
    private(set) var attemptCount = 0

    init(failuresBeforeSuccess: Int) {
        self.failuresBeforeSuccess = failuresBeforeSuccess
    }

    func failAllRequests() {
        alwaysFail = true
    }

    func fetchAircraft(in bounds: MapBounds) async throws -> AircraftSnapshot {
        attemptCount += 1
        if alwaysFail || attemptCount <= failuresBeforeSuccess {
            throw APIError.offline
        }
        return AircraftSnapshot(
            aircraft: [],
            fetchTimestamp: Date(),
            providerName: "Flaky Test Provider",
            isStale: false,
            isPartial: false
        )
    }

    func fetchAircraft(icao24: String) async throws -> Aircraft? { nil }

    func fetchTrack(icao24: String) async throws -> AircraftTrack {
        AircraftTrack(icao24: icao24, coordinates: [])
    }
}
