import Foundation

enum HTTPMethod: String, Sendable {
    case get = "GET"
}

struct Endpoint<Response: Decodable & Sendable>: Sendable {
    let baseURL: URL
    let path: String
    var method: HTTPMethod = .get
    var queryItems: [URLQueryItem] = []
    var headers: [String: String] = [:]
    var timeout: TimeInterval?

    func makeRequest(defaultTimeout: TimeInterval) throws -> URLRequest {
        let url = baseURL.appending(path: path)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let resolvedURL = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: resolvedURL)
        request.httpMethod = method.rawValue
        request.timeoutInterval = timeout ?? defaultTimeout
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }
}
