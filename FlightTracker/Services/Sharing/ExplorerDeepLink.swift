import Foundation

enum ExplorerDeepLink: Equatable, Sendable {
    case aircraft(icao24: String, latitude: Double, longitude: Double, span: Double)
    case airport(id: String, latitude: Double, longitude: Double, span: Double)

    var url: URL {
        let kind: String, identifier: String, latitude: Double, longitude: Double, span: Double
        switch self {
        case .aircraft(let id, let lat, let lon, let zoom): (kind, identifier, latitude, longitude, span) = ("aircraft", id, lat, lon, zoom)
        case .airport(let id, let lat, let lon, let zoom): (kind, identifier, latitude, longitude, span) = ("airport", id, lat, lon, zoom)
        }
        var components = URLComponents()
        components.scheme = "flighttracker"
        components.host = kind
        components.path = "/\(identifier)"
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lon", value: String(longitude)),
            URLQueryItem(name: "span", value: String(span))
        ]
        return components.url!
    }

    init?(url: URL) {
        guard url.scheme == "flighttracker", let kind = url.host else { return nil }
        let id = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let values = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
        guard !id.isEmpty,
              let latitude = values["lat"].flatMap(Double.init),
              let longitude = values["lon"].flatMap(Double.init),
              let span = values["span"].flatMap(Double.init) else { return nil }
        switch kind {
        case "aircraft": self = .aircraft(icao24: id, latitude: latitude, longitude: longitude, span: span)
        case "airport": self = .airport(id: id, latitude: latitude, longitude: longitude, span: span)
        default: return nil
        }
    }
}
