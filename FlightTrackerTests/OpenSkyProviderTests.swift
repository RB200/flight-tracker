import XCTest
@testable import FlightTracker

final class OpenSkyProviderTests: XCTestCase {
    func testDecodingNormalizesStateVectorAndTrimsCallsign() throws {
        let response = try JSONDecoder().decode(OpenSkyStateResponse.self, from: Self.stateData)
        let aircraft = try XCTUnwrap(response.normalizedAircraft(providerName: "OpenSky Network").first)

        XCTAssertEqual(aircraft.icao24, "abc123")
        XCTAssertEqual(aircraft.callsign, "TEST123")
        XCTAssertEqual(aircraft.originCountry, "United States")
        XCTAssertEqual(aircraft.coordinate.latitude, 37.62, accuracy: 0.001)
        XCTAssertEqual(aircraft.coordinate.longitude, -122.38, accuracy: 0.001)
        XCTAssertEqual(aircraft.barometricAltitudeMeters, 10_000)
        XCTAssertEqual(aircraft.groundSpeedMetersPerSecond, 230)
        XCTAssertEqual(aircraft.headingDegrees, 270)
        XCTAssertEqual(aircraft.verticalRateMetersPerSecond, -2.5)
        XCTAssertEqual(aircraft.squawk, "1200")
        XCTAssertEqual(aircraft.dataSource, "OpenSky Network")
    }

    func testMalformedRowsAreSkippedWithoutFailingResponse() throws {
        let response = try JSONDecoder().decode(OpenSkyStateResponse.self, from: Self.stateData)

        XCTAssertEqual(response.stateVectors.count, 1)
    }

    func testEmptyCallsignNormalizesToNil() throws {
        let data = Data(#"{"time":1700000000,"states":[["abc123","   ","US",1700000000,1700000000,-122.0,37.0,1000,false,100,90,0,null,1100,"1200",false,0]]}"#.utf8)
        let response = try JSONDecoder().decode(OpenSkyStateResponse.self, from: data)

        XCTAssertNil(response.stateVectors.first?.callsign)
    }

    func testTrackDecoderSkipsMalformedWaypoints() throws {
        let data = Data(#"{"icao24":"abc123","startTime":1,"endTime":2,"calllsign":"TEST","path":[[1,37.0,-122.0,1000,90,false],[2,null,-121.0,1100,95,false],[3,91.0,-121.0,1100,95,false]]}"#.utf8)
        let response = try JSONDecoder().decode(OpenSkyTrackResponse.self, from: data)

        XCTAssertEqual(response.waypoints.count, 1)
        XCTAssertEqual(response.waypoints.first?.coordinate.latitude, 37)
    }

    func testProviderUsesInjectedClientAndNormalizesResponse() async throws {
        let recorder = RequestURLRecorder()
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com/api/states/all")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let client = APIClient(
            transport: HTTPTransport { request in
                await recorder.record(request.url)
                return (Self.stateData, response)
            },
            retryPolicy: RetryPolicy(maximumRetryCount: 0)
        )
        let provider = OpenSkyProvider(client: client, baseURL: URL(string: "https://example.com/api")!)

        let snapshot = try await provider.fetchAircraft(in: .continentalUnitedStates)
        let recordedURL = await recorder.url
        let requestURL = try XCTUnwrap(recordedURL)
        let items = try XCTUnwrap(URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?.queryItems)

        XCTAssertEqual(snapshot.aircraft.count, 1)
        XCTAssertEqual(snapshot.providerName, "OpenSky Network")
        XCTAssertEqual(Set(items.map(\.name)), Set(["lamin", "lomin", "lamax", "lomax"]))
    }

    private static let stateData = Data(#"{"time":1700000000,"states":[["ABC123"," TEST123 ","United States",1699999998,1699999999,-122.38,37.62,10000,false,230,270,-2.5,[1],10100,"1200",false,0],["too-short"],["def456","BAD","US",1700000000,1700000000,null,40.0,1000,false,100,90,0,null,1100,null,false,0]]}"#.utf8)
}

private actor RequestURLRecorder {
    private(set) var url: URL?
    func record(_ url: URL?) { self.url = url }
}
