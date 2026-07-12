import CoreLocation
import XCTest
@testable import FlightTracker

final class LivePollingTests: XCTestCase {
    func testAntimeridianFetchesBothSidesAndDeduplicatesNewestAircraft() async throws {
        let provider = AntimeridianProvider(failWesternSide: false)
        let service = AircraftPollingService(provider: provider, retryPolicy: PollingRetryPolicy(maximumRetryCount: 0))
        let bounds = try MapBounds(minimumLatitude: -10, minimumLongitude: 170, maximumLatitude: 10, maximumLongitude: -170)

        let snapshot = try await service.fetchSnapshot(in: bounds)
        let callCount = await provider.callCount

        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(snapshot.aircraft.count, 1)
        XCTAssertEqual(snapshot.aircraft.first?.callsign, "NEWER")
        XCTAssertFalse(snapshot.isPartial)
    }

    func testAntimeridianMarksSnapshotPartialWhenOneSideFails() async throws {
        let provider = AntimeridianProvider(failWesternSide: true)
        let service = AircraftPollingService(provider: provider, retryPolicy: PollingRetryPolicy(maximumRetryCount: 0))
        let bounds = try MapBounds(minimumLatitude: -10, minimumLongitude: 170, maximumLatitude: 10, maximumLongitude: -170)

        let snapshot = try await service.fetchSnapshot(in: bounds)

        XCTAssertTrue(snapshot.isPartial)
        XCTAssertEqual(snapshot.aircraft.count, 1)
    }

    func testCancellationStopsObsoleteFetch() async throws {
        let provider = SlowProvider()
        let service = AircraftPollingService(provider: provider, retryPolicy: PollingRetryPolicy(maximumRetryCount: 0))
        let task = Task { try await service.fetchSnapshot(in: .continentalUnitedStates) }
        try await Task.sleep(for: .milliseconds(30))
        await service.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
        let cancellationCount = await provider.cancellationCount
        XCTAssertEqual(cancellationCount, 1)
    }

    func testPollingPausesWhileApplicationInactiveAndResumesImmediately() async throws {
        var configuration = AircraftRequestConfiguration()
        configuration.pollingInterval = .milliseconds(30)
        let provider = CountingProvider()
        let service = AircraftPollingService(provider: provider, configuration: configuration)
        await service.setViewport(try MapBounds(minimumLatitude: 30, minimumLongitude: -100, maximumLatitude: 35, maximumLongitude: -95))
        await service.setApplicationActive(false)
        await service.start()
        try await Task.sleep(for: .milliseconds(80))
        let inactiveCount = await provider.callCount
        await service.setApplicationActive(true)
        try await Task.sleep(for: .milliseconds(80))
        await service.stop()
        let activeCount = await provider.callCount

        XCTAssertEqual(inactiveCount, 0)
        XCTAssertGreaterThanOrEqual(activeCount, 1)
        let maximumConcurrentCalls = await provider.maximumConcurrentCalls
        XCTAssertEqual(maximumConcurrentCalls, 1)
    }
}

private actor AntimeridianProvider: AircraftProvider {
    let failWesternSide: Bool
    private(set) var callCount = 0

    init(failWesternSide: Bool) { self.failWesternSide = failWesternSide }

    func fetchAircraft(in bounds: MapBounds) async throws -> AircraftSnapshot {
        callCount += 1
        let western = bounds.minimumLongitude < 0
        if western && failWesternSide { throw APIError.offline }
        let date = Date().addingTimeInterval(western ? 10 : 0)
        let aircraft = Aircraft(
            id: "abc123", icao24: "abc123", callsign: western ? "NEWER" : "OLDER",
            originCountry: nil,
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: western ? -179 : 179),
            barometricAltitudeMeters: nil, geometricAltitudeMeters: nil,
            groundSpeedMetersPerSecond: nil, headingDegrees: nil, verticalRateMetersPerSecond: nil,
            squawk: nil, isOnGround: false, lastContact: date,
            positionTimestamp: date, dataSource: "Test"
        )
        return AircraftSnapshot(aircraft: [aircraft], fetchTimestamp: date, providerName: "Test", isStale: false, isPartial: false)
    }

    func fetchAircraft(icao24: String) async throws -> Aircraft? { nil }
    func fetchTrack(icao24: String) async throws -> AircraftTrack { AircraftTrack(icao24: icao24, coordinates: []) }
}

private actor SlowProvider: AircraftProvider {
    private(set) var cancellationCount = 0
    func fetchAircraft(in bounds: MapBounds) async throws -> AircraftSnapshot {
        do { try await Task.sleep(for: .seconds(10)) }
        catch { cancellationCount += 1; throw CancellationError() }
        return AircraftSnapshot(aircraft: [], fetchTimestamp: Date(), providerName: "Slow", isStale: false, isPartial: false)
    }
    func fetchAircraft(icao24: String) async throws -> Aircraft? { nil }
    func fetchTrack(icao24: String) async throws -> AircraftTrack { AircraftTrack(icao24: icao24, coordinates: []) }
}

private actor CountingProvider: AircraftProvider {
    private(set) var callCount = 0
    private(set) var maximumConcurrentCalls = 0
    private var concurrentCalls = 0
    func fetchAircraft(in bounds: MapBounds) async throws -> AircraftSnapshot {
        callCount += 1
        concurrentCalls += 1
        maximumConcurrentCalls = max(maximumConcurrentCalls, concurrentCalls)
        try await Task.sleep(for: .milliseconds(10))
        concurrentCalls -= 1
        return AircraftSnapshot(aircraft: [], fetchTimestamp: Date(), providerName: "Count", isStale: false, isPartial: false)
    }
    func fetchAircraft(icao24: String) async throws -> Aircraft? { nil }
    func fetchTrack(icao24: String) async throws -> AircraftTrack { AircraftTrack(icao24: icao24, coordinates: []) }
}
