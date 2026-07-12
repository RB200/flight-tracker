import Foundation

struct AircraftRequestConfiguration: Sendable, Equatable {
    var pollingInterval: Duration = .seconds(10)
    var viewportDebounce: Duration = .milliseconds(400)
    var staleThreshold: Duration = .seconds(30)
    var removalThreshold: Duration = .seconds(90)
    var viewportPaddingFraction: Double = 0.1
    var maximumLatitudeSpan: Double = 20
    var maximumLongitudeSpan: Double = 30

    func accepts(_ bounds: MapBounds) -> Bool {
        bounds.latitudeSpan <= maximumLatitudeSpan && bounds.longitudeSpan <= maximumLongitudeSpan
    }
}

enum AircraftFreshness: Sendable, Equatable {
    case fresh
    case stale
    case expired
}

struct ViewportRequest: Sendable, Equatable {
    let id: UUID
    let bounds: MapBounds
    let createdAt: Date

    init(id: UUID = UUID(), bounds: MapBounds, createdAt: Date = Date()) {
        self.id = id
        self.bounds = bounds
        self.createdAt = createdAt
    }
}

enum ProviderStatus: Sendable, Equatable {
    case idle
    case loading
    case live(providerName: String, aircraftCount: Int, updatedAt: Date)
    case stale(providerName: String, updatedAt: Date)
    case offline
    case rateLimited(retryAfter: TimeInterval?)
    case partial(providerName: String, aircraftCount: Int)
    case failed(message: String)
    case viewportTooLarge
}

extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}
