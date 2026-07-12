import CoreLocation
import XCTest
@testable import FlightTracker

final class AircraftFreshnessTests: XCTestCase {
    func testFreshStaleAndExpiredThresholds() {
        let now = Date()
        XCTAssertEqual(makeAircraft(lastContact: now.addingTimeInterval(-29)).freshness(at: now, staleThreshold: .seconds(30), removalThreshold: .seconds(90)), .fresh)
        XCTAssertEqual(makeAircraft(lastContact: now.addingTimeInterval(-30)).freshness(at: now, staleThreshold: .seconds(30), removalThreshold: .seconds(90)), .stale)
        XCTAssertEqual(makeAircraft(lastContact: now.addingTimeInterval(-90)).freshness(at: now, staleThreshold: .seconds(30), removalThreshold: .seconds(90)), .expired)
    }

    private func makeAircraft(lastContact: Date) -> Aircraft {
        Aircraft(
            id: "abc123", icao24: "abc123", callsign: nil, originCountry: nil,
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            barometricAltitudeMeters: nil, geometricAltitudeMeters: nil,
            groundSpeedMetersPerSecond: nil, headingDegrees: nil, verticalRateMetersPerSecond: nil,
            squawk: nil, isOnGround: false, lastContact: lastContact,
            positionTimestamp: lastContact, dataSource: "Test"
        )
    }
}
