import CoreLocation
import Foundation

struct AircraftTrailPoint: Sendable, Equatable {
    let coordinate: CLLocationCoordinate2D
    let altitude: Double?
    let timestamp: Date

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.altitude == rhs.altitude
            && lhs.timestamp == rhs.timestamp
    }
}
