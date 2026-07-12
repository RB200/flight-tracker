import MapKit

@MainActor
final class AirportAnnotation: NSObject, @preconcurrency MKAnnotation {
    let airport: Airport
    var coordinate: CLLocationCoordinate2D { airport.coordinate }
    var title: String? { airport.displayCode }
    var subtitle: String? { airport.name }

    init(airport: Airport) { self.airport = airport }
}

@MainActor
final class AirportAnnotationView: MKMarkerAnnotationView {
    static let reuseIdentifier = "AirportAnnotationView"

    override var annotation: (any MKAnnotation)? {
        didSet { applyAirport() }
    }

    private func applyAirport() {
        guard let annotation = annotation as? AirportAnnotation else { return }
        markerTintColor = .systemIndigo
        glyphImage = UIImage(systemName: annotation.airport.type == .heliport ? "h.circle.fill" : "building.2.fill")
        displayPriority = annotation.airport.type == .large ? .required : .defaultLow
        clusteringIdentifier = "airport"
        canShowCallout = false
        titleVisibility = annotation.airport.type == .large ? .visible : .adaptive
        accessibilityLabel = "\(annotation.airport.name), \(annotation.airport.displayCode) airport"
        accessibilityIdentifier = "airport-\(annotation.airport.id)"
    }
}
