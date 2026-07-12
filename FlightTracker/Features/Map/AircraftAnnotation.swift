import MapKit

@MainActor
final class AircraftAnnotation: NSObject, @preconcurrency MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    private(set) var aircraft: Aircraft

    var title: String? { aircraft.callsign ?? aircraft.icao24.uppercased() }
    var subtitle: String? { aircraft.originCountry }

    init(aircraft: Aircraft) {
        self.aircraft = aircraft
        coordinate = aircraft.coordinate
        super.init()
    }

    func update(with aircraft: Aircraft) {
        let coordinateChanged = coordinate.latitude != aircraft.coordinate.latitude
            || coordinate.longitude != aircraft.coordinate.longitude
        self.aircraft = aircraft
        if coordinateChanged {
            coordinate = aircraft.coordinate
        }
    }
}
