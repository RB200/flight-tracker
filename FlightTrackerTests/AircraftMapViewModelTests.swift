import CoreLocation
import MapKit
import XCTest
@testable import FlightTracker

@MainActor
final class AircraftMapViewModelTests: XCTestCase {
    func testAnnotationHighlightTracksMapSelection() {
        let view = AircraftAnnotationView(annotation: nil, reuseIdentifier: AircraftAnnotationView.reuseIdentifier)

        XCTAssertFalse(view.isVisuallyHighlighted)
        view.isSelected = true
        XCTAssertTrue(view.isVisuallyHighlighted)
        view.isSelected = false
        XCTAssertFalse(view.isVisuallyHighlighted)
    }

    func testLoadPublishesAircraftAndLoadedState() async {
        let service = AircraftPollingService(provider: MockAircraftProvider(aircraftCount: 12))
        let viewModel = AircraftMapViewModel(pollingService: service)

        await viewModel.load()

        XCTAssertEqual(viewModel.aircraft.count, 12)
        XCTAssertEqual(viewModel.loadState, .loaded)
        XCTAssertNotNil(viewModel.lastUpdateTime)
        guard case .live(let name, _, _) = viewModel.providerStatus else {
            return XCTFail("Expected available provider status")
        }
        XCTAssertEqual(name, "Seeded Mock ADS-B")
    }

    func testSelectionCanBeSetAndCleared() async {
        let service = AircraftPollingService(provider: MockAircraftProvider(aircraftCount: 1))
        let viewModel = AircraftMapViewModel(pollingService: service)
        await viewModel.load()

        viewModel.select(viewModel.aircraft.first)
        XCTAssertEqual(viewModel.selectedAircraft, viewModel.aircraft.first)

        viewModel.select(nil)
        XCTAssertNil(viewModel.selectedAircraft)
    }

    func testProviderFailureBecomesDisplayableState() async {
        let service = AircraftPollingService(
            provider: FailingProvider(),
            retryPolicy: PollingRetryPolicy(maximumRetryCount: 0)
        )
        let viewModel = AircraftMapViewModel(pollingService: service)

        await viewModel.load()

        guard case .failed(let message) = viewModel.loadState else {
            return XCTFail("Expected failed state")
        }
        XCTAssertFalse(message.isEmpty)
    }

    func testSelectionSurvivesRefreshThatTemporarilyOmitsAircraft() async {
        let provider = SelectionSequenceProvider()
        let service = AircraftPollingService(provider: provider)
        let viewModel = AircraftMapViewModel(pollingService: service)
        await viewModel.load()
        viewModel.select(viewModel.aircraft.first)

        await viewModel.load()

        XCTAssertEqual(viewModel.selectedAircraft?.icao24, "abc123")
        XCTAssertEqual(viewModel.selectedAircraft?.freshness, .stale)
        XCTAssertTrue(viewModel.aircraft.contains { $0.icao24 == "abc123" })
    }
}

private actor SelectionSequenceProvider: AircraftProvider {
    private var requestCount = 0

    func fetchAircraft(in bounds: MapBounds) async throws -> AircraftSnapshot {
        requestCount += 1
        let aircraft: [Aircraft]
        if requestCount == 1 {
            let now = Date()
            aircraft = [Aircraft(
                id: "abc123", icao24: "abc123", callsign: "TEST123", originCountry: nil,
                coordinate: CLLocationCoordinate2D(latitude: 35, longitude: -100),
                barometricAltitudeMeters: nil, geometricAltitudeMeters: nil,
                groundSpeedMetersPerSecond: nil, headingDegrees: nil, verticalRateMetersPerSecond: nil,
                squawk: nil, isOnGround: false, lastContact: now,
                positionTimestamp: now, dataSource: "Test"
            )]
        } else {
            aircraft = []
        }
        return AircraftSnapshot(
            aircraft: aircraft,
            fetchTimestamp: Date(),
            providerName: "Test",
            isStale: false,
            isPartial: false
        )
    }

    func fetchAircraft(icao24: String) async throws -> Aircraft? { nil }
    func fetchTrack(icao24: String) async throws -> AircraftTrack { AircraftTrack(icao24: icao24, coordinates: []) }
}

private struct FailingProvider: AircraftProvider {
    func fetchAircraft(in bounds: MapBounds) async throws -> AircraftSnapshot {
        throw APIError.offline
    }

    func fetchAircraft(icao24: String) async throws -> Aircraft? {
        throw APIError.offline
    }

    func fetchTrack(icao24: String) async throws -> AircraftTrack {
        throw APIError.offline
    }
}
