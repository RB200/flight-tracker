import XCTest

@MainActor
final class FlightTrackerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLoadsMapAndMockAircraft() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSlowInitialLoad", "-UITestDisableMotion"]
        app.launch()

        XCTAssertTrue(app.otherElements["aircraft-map"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["loading-indicator"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["aircraft-count"].waitForExistence(timeout: 40))
        XCTAssertTrue(app.descendants(matching: .any)["safety-disclaimer"].exists)
    }

    func testSelectingAircraftPresentsDetails() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFastPolling", "-UITestWideLimits", "-UITestDisableMotion"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["aircraft-count"].waitForExistence(timeout: 40))
        let aircraftQuery = app.otherElements.matching(
            NSPredicate(format: "identifier BEGINSWITH 'aircraft-'")
        )
        let annotation = (0..<min(aircraftQuery.count, 50))
            .map { aircraftQuery.element(boundBy: $0) }
            .first(where: \.isHittable)
        guard let annotation else {
            return XCTFail("Expected a hittable aircraft annotation")
        }
        annotation.tap()

        XCTAssertTrue(app.descendants(matching: .any)["aircraft-details-sheet"].waitForExistence(timeout: 3))
        let follow = app.descendants(matching: .any)["follow-aircraft"]
        XCTAssertTrue(follow.waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["toggle-trail"].exists)
        follow.tap()
        sleep(6)
        XCTAssertTrue(app.descendants(matching: .any)["details-callsign"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["close-details"].exists)
    }

    func testStaleCacheWarningAppearsAfterTemporaryFailure() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFastPolling", "-UITestStaleProvider", "-UITestDisableMotion"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["aircraft-count"].waitForExistence(timeout: 25))
        XCTAssertTrue(app.descendants(matching: .any)["stale-warning"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.descendants(matching: .any)["offline-warning"].exists)
    }

    func testOversizedViewportAsksUserToZoomIn() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFastPolling", "-UITestDisableMotion"]
        app.launch()
        let map = app.otherElements["aircraft-map"]
        XCTAssertTrue(map.waitForExistence(timeout: 5))

        map.pinch(withScale: 0.2, velocity: -4)

        XCTAssertTrue(app.descendants(matching: .any)["viewport-too-large-warning"].waitForExistence(timeout: 5))
    }

    func testAirportSearchSelectionAndFilters() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFastPolling", "-UITestDisableMotion"]
        app.launch()

        let search = app.descendants(matching: .any)["global-search-field"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        search.tap()
        search.typeText("LAX")
        let result = app.descendants(matching: .any)["search-result-airport:KLAX"]
        XCTAssertTrue(result.waitForExistence(timeout: 15))
        result.tap()
        XCTAssertTrue(app.descendants(matching: .any)["airport-details-sheet"].waitForExistence(timeout: 5))
        app.buttons["close-airport-details"].tap()

        let filters = app.buttons["open-filters"]
        XCTAssertTrue(filters.waitForExistence(timeout: 5))
        filters.tap()
        XCTAssertTrue(app.descendants(matching: .any)["aircraft-filter-sheet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["reset-filters"].exists)
        app.buttons["close-filters"].tap()
    }
}
