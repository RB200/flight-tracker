import Foundation
import OSLog

struct NetworkLogger: Sendable {
    private let logger: Logger

    init(subsystem: String = "com.example.FlightTracker") {
        logger = Logger(subsystem: subsystem, category: "Networking")
    }

    func requestStarted(_ request: URLRequest, attempt: Int) {
        logger.debug("Request started: \(request.httpMethod ?? "GET", privacy: .public) \(request.url?.path ?? "", privacy: .public), attempt \(attempt)")
    }

    func requestFinished(_ request: URLRequest, statusCode: Int, duration: TimeInterval) {
        logger.debug("Request finished: \(request.url?.path ?? "", privacy: .public), status \(statusCode), \(duration, format: .fixed(precision: 3))s")
    }

    func requestFailed(_ request: URLRequest, error: APIError) {
        logger.error("Request failed: \(request.url?.path ?? "", privacy: .public), \(error.localizedDescription, privacy: .public)")
    }
}
