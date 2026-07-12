import MapKit
import XCTest
@testable import FlightTracker

final class MapBoundsTests: XCTestCase {
    func testRejectsInvalidAndNonFiniteCoordinates() {
        XCTAssertThrowsError(try MapBounds(minimumLatitude: -91, minimumLongitude: 0, maximumLatitude: 10, maximumLongitude: 20))
        XCTAssertThrowsError(try MapBounds(minimumLatitude: 0, minimumLongitude: .nan, maximumLatitude: 10, maximumLongitude: 20))
        XCTAssertThrowsError(try MapBounds(minimumLatitude: 0, minimumLongitude: 0, maximumLatitude: .infinity, maximumLongitude: 20))
    }

    func testAntimeridianBoundsSplitIntoTwoValidRequests() throws {
        let bounds = try MapBounds(
            minimumLatitude: -10,
            minimumLongitude: 170,
            maximumLatitude: 10,
            maximumLongitude: -170
        )

        XCTAssertTrue(bounds.crossesAntimeridian)
        XCTAssertEqual(bounds.longitudeSpan, 20)
        XCTAssertEqual(bounds.center.longitude, 180)
        XCTAssertEqual(bounds.splitAtAntimeridian().count, 2)
        XCTAssertTrue(bounds.splitAtAntimeridian().allSatisfy { !$0.crossesAntimeridian })
    }

    func testRegionPaddingClampsLatitudeAndNormalizesLongitude() {
        let bounds = MapBounds(
            region: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 88, longitude: 179),
                span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10)
            ),
            paddingFraction: 0.1
        )

        XCTAssertEqual(bounds.maximumLatitude, 90)
        XCTAssertTrue(bounds.crossesAntimeridian)
        XCTAssertEqual(bounds.longitudeSpan, 12, accuracy: 0.001)
    }

    func testRequestConfigurationRejectsOversizedViewport() throws {
        let bounds = try MapBounds(minimumLatitude: 0, minimumLongitude: 0, maximumLatitude: 21, maximumLongitude: 20)
        XCTAssertFalse(AircraftRequestConfiguration().accepts(bounds))
    }
}
