import XCTest
@testable import FlightTracker

final class APIClientTests: XCTestCase {
    func testTransientServerFailureRetriesWithExponentialBackoff() async throws {
        let script = RetryScript(failuresBeforeSuccess: 2)
        let delays = DelayRecorder()
        let client = APIClient(
            transport: HTTPTransport { request in try await script.response(for: request) },
            retryPolicy: RetryPolicy(maximumRetryCount: 2, baseDelay: 0.25, maximumDelay: 2),
            sleeper: RetrySleeper { seconds in await delays.record(seconds) }
        )
        let endpoint = Endpoint<TestPayload>(baseURL: URL(string: "https://example.com")!, path: "states")

        let payload = try await client.send(endpoint)
        let attemptCount = await script.attemptCount
        let recordedDelays = await delays.values

        XCTAssertEqual(payload.value, 42)
        XCTAssertEqual(attemptCount, 3)
        XCTAssertEqual(recordedDelays, [0.25, 0.5])
    }

    func testUnauthorizedDoesNotRetry() async {
        let script = RetryScript(statusCode: 401)
        let client = APIClient(
            transport: HTTPTransport { request in try await script.response(for: request) },
            retryPolicy: RetryPolicy(maximumRetryCount: 3)
        )
        let endpoint = Endpoint<TestPayload>(baseURL: URL(string: "https://example.com")!, path: "states")

        do {
            _ = try await client.send(endpoint)
            XCTFail("Expected unauthorized error")
        } catch {
            let attemptCount = await script.attemptCount
            XCTAssertEqual(error as? APIError, .unauthorized)
            XCTAssertEqual(attemptCount, 1)
        }
    }

    func testRetryAfterSecondsHeaderIsParsed() {
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 429,
            httpVersion: nil,
            headerFields: ["Retry-After": "12"]
        )!

        XCTAssertEqual(APIClient.retryAfter(from: response), 12)
    }

    func testDecodingErrorIsStructured() async {
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let client = APIClient(
            transport: HTTPTransport { _ in (Data("not json".utf8), response) },
            retryPolicy: RetryPolicy(maximumRetryCount: 0)
        )
        let endpoint = Endpoint<TestPayload>(baseURL: URL(string: "https://example.com")!, path: "states")

        do {
            _ = try await client.send(endpoint)
            XCTFail("Expected decoding error")
        } catch {
            guard case .decoding = error as? APIError else {
                return XCTFail("Expected structured decoding error")
            }
        }
    }
}

private struct TestPayload: Codable, Sendable {
    let value: Int
}

private actor RetryScript {
    private let failuresBeforeSuccess: Int
    private let statusCode: Int?
    private(set) var attemptCount = 0

    init(failuresBeforeSuccess: Int = 0, statusCode: Int? = nil) {
        self.failuresBeforeSuccess = failuresBeforeSuccess
        self.statusCode = statusCode
    }

    func response(for request: URLRequest) throws -> (Data, HTTPURLResponse) {
        attemptCount += 1
        let code = statusCode ?? (attemptCount <= failuresBeforeSuccess ? 503 : 200)
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
        return (Data(#"{"value":42}"#.utf8), response)
    }
}

private actor DelayRecorder {
    private(set) var values: [TimeInterval] = []

    func record(_ value: TimeInterval) {
        values.append(value)
    }
}
