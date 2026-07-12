import CoreLocation
import XCTest
@testable import FlightTracker

final class ExplorerTests: XCTestCase {
    func testSearchRanksExactAirportCodeBeforePrefixAndFuzzyMatches() async {
        let index = InMemorySearchIndex()
        let lax = airport(id: "KLAX", iata: "LAX", name: "Los Angeles International Airport")
        let laa = airport(id: "KLAA", iata: "LAA", name: "Lamar Municipal Airport")
        await index.replace(scope: .airport, with: [lax, laa].map(SearchDocument.airport))

        let results = await index.search("LAX")

        XCTAssertEqual(results.first?.result, .airport(lax))
        XCTAssertGreaterThan(results.first?.score ?? 0, results.dropFirst().first?.score ?? 0)
    }

    func testSearchSuggestionsUseIndexedPrefixes() async {
        let index = InMemorySearchIndex()
        let airport = airport(id: "KSFO", iata: "SFO", name: "San Francisco International Airport")
        await index.replace(scope: .airport, with: [SearchDocument.airport(airport)])

        let suggestions = await index.suggestions(for: "San Fran")
        XCTAssertEqual(suggestions.first, airport.name)
    }

    func testAirportMetadataDecodingAndLookup() async throws {
        let source = airport(id: "KSEA", iata: "SEA", name: "Seattle-Tacoma International Airport")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        try JSONEncoder().encode([source]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let database = AirportDatabase(resourceURL: url)

        let loaded = try await database.load()

        XCTAssertEqual(loaded, [source])
        let match = await database.airport(code: "sea")
        XCTAssertEqual(match, source)
        XCTAssertEqual(source.runways.first?.lengthFeet, 12_000)
    }

    func testFiltersApplyAllSupportedMetadata() {
        var filter = AircraftFilter()
        filter.minimumAltitudeFeet = 30_000
        filter.maximumSpeedKnots = 500
        filter.aircraftTypes = [.jet]
        filter.airlineICAOs = ["AAL"]
        filter.countries = ["United States"]
        filter.airborne = true
        filter.freshness = .fresh
        filter.wakeCategories = [.medium]
        filter.engineTypes = [.jet]
        filter.operators = ["American Airlines"]

        XCTAssertTrue(filter.includes(aircraft()))
        var rejected = aircraft()
        rejected.aircraftType = .helicopter
        XCTAssertFalse(filter.includes(rejected))
    }

    @MainActor
    func testFavoritesToggleWithoutPersistence() {
        let favorites = FavoritesStore()
        favorites.toggle(.airport("KLAX"))
        XCTAssertTrue(favorites.contains(.airport("KLAX")))
        favorites.toggle(.airport("KLAX"))
        XCTAssertFalse(favorites.contains(.airport("KLAX")))
    }

    @MainActor
    func testAirportSelectionAndAirlineSearchSelection() {
        let model = AircraftMapViewModel(pollingService: AircraftPollingService(provider: MockAircraftProvider(aircraftCount: 1)))
        let airport = airport(id: "KJFK", iata: "JFK", name: "John F Kennedy International Airport")

        model.selectAirport(airport)
        XCTAssertEqual(model.selectedAirport, airport)
        XCTAssertEqual(model.presentedSheet, .airport)

        model.selectSearchResult(.airline(Airline.builtIn[0]))
        XCTAssertEqual(model.filter.airlineICAOs, ["AAL"])
        XCTAssertEqual(model.presentedSheet, .filters)
    }

    func testShareLinkRoundTripsMapSelectionAndZoom() throws {
        let source = ExplorerDeepLink.aircraft(icao24: "a0b1c2", latitude: 37.6, longitude: -122.3, span: 1.25)
        XCTAssertEqual(ExplorerDeepLink(url: source.url), source)
    }

    func testTenThousandDocumentSearchIndex() async {
        let index = InMemorySearchIndex()
        let documents = (0..<10_000).map { number in
            SearchDocument.airport(airport(id: String(format: "K%04d", number), iata: nil, name: "Indexed Airport \(number)"))
        }
        await index.replace(scope: .airport, with: documents)
        let start = ContinuousClock.now
        let results = await index.search("Indexed Airport 9999")
        let elapsed = start.duration(to: .now)

        XCTAssertEqual(results.first?.result.title, "Indexed Airport 9999")
        XCTAssertLessThan(elapsed, .milliseconds(250))
    }

    private func airport(id: String, iata: String?, name: String) -> Airport {
        Airport(
            id: id, icao: id, iata: iata, name: name, latitude: 34, longitude: -118,
            elevationFeet: 125, country: "US", city: "Test City", timezone: "America/Los_Angeles",
            type: .large, runways: [AirportRunway(name: "07/25", lengthFeet: 12_000, surface: "ASP")]
        )
    }

    private func aircraft() -> Aircraft {
        Aircraft(
            id: "abc123", icao24: "abc123", callsign: "AAL100", originCountry: "United States",
            coordinate: CLLocationCoordinate2D(latitude: 35, longitude: -110),
            barometricAltitudeMeters: 10_000, geometricAltitudeMeters: 10_050,
            groundSpeedMetersPerSecond: 220, headingDegrees: 90, verticalRateMetersPerSecond: 1,
            squawk: "1200", isOnGround: false, lastContact: .now, positionTimestamp: .now,
            dataSource: "Test", flightNumber: "AA 100", registration: "N123AA",
            manufacturer: "Boeing", model: "737-800", aircraftType: .jet,
            operatorName: "American Airlines", airline: Airline.builtIn[0], hexCode: "ABC123",
            wakeCategory: .medium, engineCount: 2, engineType: .jet
        )
    }
}
