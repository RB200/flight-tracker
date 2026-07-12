import CoreLocation
import XCTest
@testable import FlightTracker

final class AircraftMotionEngineTests: XCTestCase {
    func testPositionAndAltitudeInterpolation() {
        let start = aircraft(latitude: 0, longitude: 0, heading: 90, altitude: 1_000)
        let target = aircraft(latitude: 10, longitude: 20, heading: 90, altitude: 2_000, seconds: 10)
        let result = AircraftMotionEngine.interpolate(from: start, to: target, progress: 0.5)
        XCTAssertEqual(result.coordinate.latitude, 5)
        XCTAssertEqual(result.coordinate.longitude, 10)
        XCTAssertEqual(result.barometricAltitudeMeters, 1_500)
    }

    func testHeadingUsesShortestWraparoundPath() throws {
        let result = AircraftMotionEngine.interpolate(
            from: aircraft(latitude: 0, longitude: 0, heading: 359),
            to: aircraft(latitude: 0, longitude: 0, heading: 1, seconds: 10),
            progress: 0.5
        )
        XCTAssertEqual(try XCTUnwrap(result.headingDegrees), 0, accuracy: 0.001)
    }

    func testImpossibleJumpAndBackwardsTimestampAreRejected() {
        let start = aircraft(latitude: 0, longitude: 0, heading: 0, seconds: 10)
        XCTAssertFalse(AircraftMotionEngine.isReasonableTransition(
            from: start, to: aircraft(latitude: 50, longitude: 50, heading: 0, seconds: 20), maximumJumpMeters: 100_000
        ))
        XCTAssertFalse(AircraftMotionEngine.isReasonableTransition(
            from: start, to: aircraft(latitude: 0, longitude: 0.1, heading: 0, seconds: 5), maximumJumpMeters: 100_000
        ))
    }

    func testTrailOrderingDeduplicationAndTrimming() {
        var store = AircraftTrailStore(maximumAge: 60, maximumPoints: 3, simplificationThreshold: 100)
        let now = Date(timeIntervalSince1970: 100)
        for second in [98.0, 99, 100, 101] {
            store.append(point(second: second, longitude: second / 100), icao24: "abc", now: now)
        }
        store.append(point(second: 100, longitude: 999), icao24: "abc", now: now)
        store.append(point(second: 101, longitude: 101), icao24: "abc", now: now)
        let points = store.points(for: "abc")
        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(points.map(\.timestamp), points.map(\.timestamp).sorted())
    }

    func testSimplificationPreservesEndpoints() {
        let points = (0..<50).map { point(second: Double($0), longitude: Double($0) / 100) }
        let simplified = AircraftTrailStore.simplify(points, toleranceMeters: 10)
        XCTAssertEqual(simplified.first, points.first)
        XCTAssertEqual(simplified.last, points.last)
        XCTAssertLessThan(simplified.count, points.count)
    }

    @MainActor
    func testFollowModeAndManualCancellation() {
        let model = AircraftMapViewModel(pollingService: AircraftPollingService(provider: MockAircraftProvider(aircraftCount: 1)))
        model.toggleFollow()
        XCTAssertTrue(model.isFollowingSelectedAircraft)
        model.cancelFollowForManualCamera()
        XCTAssertFalse(model.isFollowingSelectedAircraft)
    }

    private func point(second: Double, longitude: Double) -> AircraftTrailPoint {
        AircraftTrailPoint(
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: longitude),
            altitude: nil,
            timestamp: Date(timeIntervalSince1970: second)
        )
    }

    private func aircraft(
        latitude: Double,
        longitude: Double,
        heading: Double,
        altitude: Double = 1_000,
        seconds: TimeInterval = 0
    ) -> Aircraft {
        let date = Date(timeIntervalSince1970: seconds)
        return Aircraft(
            id: "abc", icao24: "abc", callsign: "TEST", originCountry: nil,
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            barometricAltitudeMeters: altitude, geometricAltitudeMeters: altitude,
            groundSpeedMetersPerSecond: 250, headingDegrees: heading, verticalRateMetersPerSecond: 0,
            squawk: nil, isOnGround: false, lastContact: date,
            positionTimestamp: date, dataSource: "Test"
        )
    }
}
