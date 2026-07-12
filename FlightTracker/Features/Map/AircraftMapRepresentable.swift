import MapKit
import SwiftUI

struct AircraftMapRepresentable: UIViewRepresentable {
    let aircraft: [Aircraft]
    let airports: [Airport]
    let selectedAircraft: Aircraft?
    let selectedAirport: Airport?
    let cameraRequest: MapCameraRequest?
    let onSelection: (Aircraft?) -> Void
    let onAirportSelection: (Airport?) -> Void
    let onViewport: (MapBounds) -> Void
    let requestConfiguration: AircraftRequestConfiguration
    let followsSelectedAircraft: Bool
    let showsSelectedTrail: Bool
    let onRenderedSelection: (Aircraft) -> Void
    let onFollowCancelled: () -> Void
    let motionEnabled: Bool

    func makeCoordinator() -> AircraftMapCoordinator {
        AircraftMapCoordinator(
            onSelection: onSelection,
            onAirportSelection: onAirportSelection,
            onViewport: onViewport,
            requestConfiguration: requestConfiguration,
            onRenderedSelection: onRenderedSelection,
            onFollowCancelled: onFollowCancelled,
            motionEnabled: motionEnabled
        )
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.register(
            AircraftAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: AircraftAnnotationView.reuseIdentifier
        )
        mapView.register(AirportAnnotationView.self, forAnnotationViewWithReuseIdentifier: AirportAnnotationView.reuseIdentifier)
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat)
        context.coordinator.setInitialRegionIfNeeded(on: mapView)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.updateSelectionHandler(onSelection)
        context.coordinator.updateAirportSelectionHandler(onAirportSelection)
        context.coordinator.updateViewportHandler(onViewport)
        context.coordinator.updateMotionOptions(
            followsSelectedAircraft: followsSelectedAircraft,
            showsSelectedTrail: showsSelectedTrail,
            onRenderedSelection: onRenderedSelection,
            onFollowCancelled: onFollowCancelled
        )
        context.coordinator.apply(
            aircraft: aircraft,
            airports: airports,
            selectedAircraft: selectedAircraft,
            selectedAirport: selectedAirport,
            cameraRequest: cameraRequest,
            to: mapView
        )
    }

    static func dismantleUIView(_ mapView: MKMapView, coordinator: AircraftMapCoordinator) {
        mapView.delegate = nil
        coordinator.stopRendering()
    }
}
