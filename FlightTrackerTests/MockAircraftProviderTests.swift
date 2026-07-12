import XCTest
@testable import FlightTracker

final class MockAircraftProviderTests: XCTestCase {
    func testProviderReturnsRequestedAircraftCount() async throws {
        let snapshot = try await MockAircraftProvider(aircraftCount: 500)
            .fetchAircraft(in: .continentalUnitedStates)

        XCTAssertEqual(snapshot.aircraft.count, 500)
        XCTAssertEqual(Set(snapshot.aircraft.map(\.icao24)).count, 500)
        XCTAssertTrue(snapshot.aircraft.allSatisfy { $0.dataSource == "Seeded Mock ADS-B" })
        XCTAssertEqual(snapshot.providerName, "Seeded Mock ADS-B")
        XCTAssertFalse(snapshot.isStale)
    }

    func testSeedMakesPositionsDeterministic() async throws {
        let first = try await MockAircraftProvider(seed: 42, aircraftCount: 3)
            .fetchAircraft(in: .continentalUnitedStates)
        let second = try await MockAircraftProvider(seed: 42, aircraftCount: 3)
            .fetchAircraft(in: .continentalUnitedStates)

        XCTAssertEqual(first.aircraft.map(\.coordinate.latitude), second.aircraft.map(\.coordinate.latitude))
        XCTAssertEqual(first.aircraft.map(\.coordinate.longitude), second.aircraft.map(\.coordinate.longitude))
        XCTAssertEqual(first.aircraft.map(\.headingDegrees), second.aircraft.map(\.headingDegrees))
    }

    func testAircraftMoveAcrossRefreshesWithoutChangingIdentity() async throws {
        let provider = MockAircraftProvider(seed: 42, aircraftCount: 50)
        let first = try await provider.fetchAircraft(in: .continentalUnitedStates)
        let second = try await provider.fetchAircraft(in: .continentalUnitedStates)
        let firstByID = Dictionary(uniqueKeysWithValues: first.aircraft.map { ($0.icao24, $0) })
        let shared = second.aircraft.compactMap { aircraft -> (Aircraft, Aircraft)? in
            firstByID[aircraft.icao24].map { ($0, aircraft) }
        }

        XCTAssertFalse(shared.isEmpty)
        XCTAssertTrue(shared.contains { before, after in
            before.freshness == .fresh && before.coordinate.latitude != after.coordinate.latitude
        })
        XCTAssertTrue(shared.allSatisfy { $0.0.callsign == $0.1.callsign })
    }

    func testAircraftStayInsideRequestedBounds() async throws {
        let bounds = try MapBounds(
            minimumLatitude: 30,
            minimumLongitude: -100,
            maximumLatitude: 31,
            maximumLongitude: -99
        )
        let snapshot = try await MockAircraftProvider(aircraftCount: 50).fetchAircraft(in: bounds)

        XCTAssertTrue(snapshot.aircraft.allSatisfy { aircraft in
            bounds.south...bounds.north ~= aircraft.coordinate.latitude
                && bounds.west...bounds.east ~= aircraft.coordinate.longitude
        })
    }
}
