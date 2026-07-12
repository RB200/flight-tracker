import Foundation

struct HTTPTransport: Sendable {
    let execute: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    static func urlSession(_ session: URLSession) -> HTTPTransport {
        HTTPTransport { request in
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            return (data, response)
        }
    }
}

struct RetryPolicy: Sendable, Equatable {
    var maximumRetryCount: Int = 2
    var baseDelay: TimeInterval = 0.5
    var maximumDelay: TimeInterval = 8
    var maximumRetryAfter: TimeInterval = 60

    func delay(forRetry retry: Int) -> TimeInterval {
        min(baseDelay * pow(2, Double(retry)), maximumDelay)
    }
}

struct RetrySleeper: Sendable {
    let sleep: @Sendable (TimeInterval) async throws -> Void

    static let continuousClock = RetrySleeper { seconds in
        try await Task.sleep(for: .seconds(seconds))
    }
}

actor APIClient {
    private let transport: HTTPTransport
    private let decoder: JSONDecoder
    private let defaultTimeout: TimeInterval
    private let retryPolicy: RetryPolicy
    private let sleeper: RetrySleeper
    private let logger: NetworkLogger

    init(
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder(),
        defaultTimeout: TimeInterval = 15,
        retryPolicy: RetryPolicy = RetryPolicy(),
        sleeper: RetrySleeper = .continuousClock,
        logger: NetworkLogger = NetworkLogger()
    ) {
        transport = .urlSession(session)
        self.decoder = decoder
        self.defaultTimeout = defaultTimeout
        self.retryPolicy = retryPolicy
        self.sleeper = sleeper
        self.logger = logger
    }

    init(
        transport: HTTPTransport,
        decoder: JSONDecoder = JSONDecoder(),
        defaultTimeout: TimeInterval = 15,
        retryPolicy: RetryPolicy = RetryPolicy(),
        sleeper: RetrySleeper = .continuousClock,
        logger: NetworkLogger = NetworkLogger()
    ) {
        self.transport = transport
        self.decoder = decoder
        self.defaultTimeout = defaultTimeout
        self.retryPolicy = retryPolicy
        self.sleeper = sleeper
        self.logger = logger
    }

    func send<Response>(_ endpoint: Endpoint<Response>) async throws -> Response {
        let request = try endpoint.makeRequest(defaultTimeout: defaultTimeout)
        var retry = 0

        while true {
            try Task.checkCancellation()
            let startedAt = Date()
            logger.requestStarted(request, attempt: retry + 1)

            do {
                let (data, response) = try await transport.execute(request)
                logger.requestFinished(request, statusCode: response.statusCode, duration: Date().timeIntervalSince(startedAt))
                try validate(response)
                do {
                    return try decoder.decode(Response.self, from: data)
                } catch {
                    throw APIError.decoding(String(describing: error))
                }
            } catch is CancellationError {
                throw APIError.cancelled
            } catch {
                let apiError = map(error)
                logger.requestFailed(request, error: apiError)
                guard shouldRetry(apiError, retry: retry) else { throw apiError }
                let delay = retryDelay(for: apiError, retry: retry)
                retry += 1
                do {
                    try await sleeper.sleep(delay)
                } catch is CancellationError {
                    throw APIError.cancelled
                }
            }
        }
    }

    private func validate(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200...299:
            return
        case 401, 403:
            throw APIError.unauthorized
        case 429:
            throw APIError.rateLimited(retryAfter: Self.retryAfter(from: response))
        case 408, 500, 502, 503, 504:
            throw APIError.server(statusCode: response.statusCode)
        default:
            throw APIError.server(statusCode: response.statusCode)
        }
    }

    private func map(_ error: Error) -> APIError {
        if let error = error as? APIError { return error }
        guard let urlError = error as? URLError else {
            return .unknown(error.localizedDescription)
        }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost:
            return .offline
        case .timedOut:
            return .timeout
        case .cancelled:
            return .cancelled
        default:
            return .transport(urlError.localizedDescription)
        }
    }

    private func shouldRetry(_ error: APIError, retry: Int) -> Bool {
        guard retry < retryPolicy.maximumRetryCount, error.isTransient else { return false }
        if case .rateLimited(let retryAfter) = error,
           let retryAfter,
           retryAfter > retryPolicy.maximumRetryAfter {
            return false
        }
        return true
    }

    private func retryDelay(for error: APIError, retry: Int) -> TimeInterval {
        if case .rateLimited(let retryAfter) = error, let retryAfter {
            return retryAfter
        }
        return retryPolicy.delay(forRetry: retry)
    }

    static func retryAfter(from response: HTTPURLResponse, now: Date = Date()) -> TimeInterval? {
        if let value = response.value(forHTTPHeaderField: "X-Rate-Limit-Retry-After-Seconds"),
           let seconds = TimeInterval(value) {
            return max(0, seconds)
        }
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        if let seconds = TimeInterval(value) {
            return max(0, seconds)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
        return formatter.date(from: value).map { max(0, $0.timeIntervalSince(now)) }
    }
}
