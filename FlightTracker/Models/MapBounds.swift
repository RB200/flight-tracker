import CoreLocation
import Foundation
import MapKit

struct MapBounds: Hashable, Sendable {
    enum ValidationError: Error, Equatable {
        case invalidLatitude
        case invalidLongitude
    }

    let minimumLatitude: Double
    let minimumLongitude: Double
    let maximumLatitude: Double
    let maximumLongitude: Double

    static let continentalUnitedStates = try! MapBounds(
        minimumLatitude: 24.4,
        minimumLongitude: -125,
        maximumLatitude: 49.4,
        maximumLongitude: -66.5
    )

    init(
        minimumLatitude: Double,
        minimumLongitude: Double,
        maximumLatitude: Double,
        maximumLongitude: Double
    ) throws {
        guard minimumLatitude.isFinite, maximumLatitude.isFinite,
              (-90...90).contains(minimumLatitude), (-90...90).contains(maximumLatitude),
              minimumLatitude <= maximumLatitude else {
            throw ValidationError.invalidLatitude
        }
        guard minimumLongitude.isFinite, maximumLongitude.isFinite,
              (-180...180).contains(minimumLongitude), (-180...180).contains(maximumLongitude) else {
            throw ValidationError.invalidLongitude
        }
        self.minimumLatitude = minimumLatitude
        self.minimumLongitude = minimumLongitude
        self.maximumLatitude = maximumLatitude
        self.maximumLongitude = maximumLongitude
    }

    init(region: MKCoordinateRegion, paddingFraction: Double = 0) {
        let centerLatitude = min(max(region.center.latitude, -90), 90)
        let centerLongitude = Self.normalizeLongitude(region.center.longitude)
        let safePadding = max(0, paddingFraction)
        let latitudeSpan = min(abs(region.span.latitudeDelta) * (1 + safePadding * 2), 180)
        let longitudeSpan = min(abs(region.span.longitudeDelta) * (1 + safePadding * 2), 360)
        let minimumLatitude = max(-90, centerLatitude - latitudeSpan / 2)
        let maximumLatitude = min(90, centerLatitude + latitudeSpan / 2)

        if longitudeSpan >= 360 {
            self = try! MapBounds(
                minimumLatitude: minimumLatitude,
                minimumLongitude: -180,
                maximumLatitude: maximumLatitude,
                maximumLongitude: 180
            )
        } else {
            self = try! MapBounds(
                minimumLatitude: minimumLatitude,
                minimumLongitude: Self.normalizeLongitude(centerLongitude - longitudeSpan / 2),
                maximumLatitude: maximumLatitude,
                maximumLongitude: Self.normalizeLongitude(centerLongitude + longitudeSpan / 2)
            )
        }
    }

    var crossesAntimeridian: Bool {
        minimumLongitude > maximumLongitude
    }

    var center: CLLocationCoordinate2D {
        let longitude: Double
        if crossesAntimeridian {
            longitude = Self.normalizeLongitude(minimumLongitude + longitudeSpan / 2)
        } else {
            longitude = (minimumLongitude + maximumLongitude) / 2
        }
        return CLLocationCoordinate2D(
            latitude: (minimumLatitude + maximumLatitude) / 2,
            longitude: longitude
        )
    }

    var latitudeSpan: Double { maximumLatitude - minimumLatitude }

    var longitudeSpan: Double {
        crossesAntimeridian
            ? (180 - minimumLongitude) + (maximumLongitude + 180)
            : maximumLongitude - minimumLongitude
    }

    var span: MKCoordinateSpan {
        MKCoordinateSpan(latitudeDelta: latitudeSpan, longitudeDelta: longitudeSpan)
    }

    var south: Double { minimumLatitude }
    var west: Double { minimumLongitude }
    var north: Double { maximumLatitude }
    var east: Double { maximumLongitude }

    func splitAtAntimeridian() -> [MapBounds] {
        guard crossesAntimeridian else { return [self] }
        return [
            try! MapBounds(
                minimumLatitude: minimumLatitude,
                minimumLongitude: minimumLongitude,
                maximumLatitude: maximumLatitude,
                maximumLongitude: 180
            ),
            try! MapBounds(
                minimumLatitude: minimumLatitude,
                minimumLongitude: -180,
                maximumLatitude: maximumLatitude,
                maximumLongitude: maximumLongitude
            )
        ]
    }

    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        guard (minimumLatitude...maximumLatitude).contains(coordinate.latitude) else { return false }
        if crossesAntimeridian {
            return coordinate.longitude >= minimumLongitude || coordinate.longitude <= maximumLongitude
        }
        return (minimumLongitude...maximumLongitude).contains(coordinate.longitude)
    }

    static func normalizeLongitude(_ longitude: Double) -> Double {
        guard longitude.isFinite else { return 0 }
        var normalized = longitude.truncatingRemainder(dividingBy: 360)
        if normalized > 180 { normalized -= 360 }
        if normalized < -180 { normalized += 360 }
        return normalized
    }
}
