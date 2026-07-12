import Foundation

enum APIError: Error, Sendable, Equatable {
    case offline
    case timeout
    case decoding(String)
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case server(statusCode: Int)
    case invalidResponse
    case invalidURL
    case cancelled
    case transport(String)
    case unknown(String)

    var isTransient: Bool {
        switch self {
        case .offline, .timeout, .rateLimited:
            true
        case .server(let statusCode):
            [408, 500, 502, 503, 504].contains(statusCode)
        case .transport:
            true
        case .decoding, .unauthorized, .invalidResponse, .invalidURL, .cancelled, .unknown:
            false
        }
    }
}

extension APIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .offline:
            "You appear to be offline."
        case .timeout:
            "The aircraft provider timed out."
        case .decoding:
            "The provider returned data in an unexpected format."
        case .unauthorized:
            "The aircraft provider rejected the credentials."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                "The provider rate limit was reached. Try again in \(Int(retryAfter.rounded(.up))) seconds."
            } else {
                "The provider rate limit was reached."
            }
        case .server(let statusCode):
            "The aircraft provider returned server error \(statusCode)."
        case .invalidResponse:
            "The aircraft provider returned an invalid response."
        case .invalidURL:
            "The aircraft provider URL is invalid."
        case .cancelled:
            "The request was cancelled."
        case .transport(let message), .unknown(let message):
            message
        }
    }
}
