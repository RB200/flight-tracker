import MapKit

@MainActor
final class AircraftMapCoordinator: NSObject, MKMapViewDelegate {
    private var annotationsByICAO24: [String: AircraftAnnotation] = [:]
    private var airportAnnotationsByID: [String: AirportAnnotation] = [:]
    private var lastTargets: [String: Aircraft] = [:]
    private var motionEngine = AircraftMotionEngine()
    private var displayLink: CADisplayLink?
    private weak var mapView: MKMapView?
    private var trailOverlay: MKPolyline?
    private var trailSignature: [CLLocationCoordinate2D] = []
    private var selectedICAO24: String?
    private var selectedAirportID: String?
    private var lastCameraRequestID: UUID?
    private var followsSelectedAircraft = false
    private var showsSelectedTrail = true
    private var lastCameraUpdate = Date.distantPast
    private var lastTelemetryUpdate = Date.distantPast
    private var isProgrammaticCameraChange = false
    private var onSelection: (Aircraft?) -> Void
    private var onAirportSelection: (Airport?) -> Void
    private var onViewport: (MapBounds) -> Void
    private var onRenderedSelection: (Aircraft) -> Void
    private var onFollowCancelled: () -> Void
    private let requestConfiguration: AircraftRequestConfiguration
    private var viewportTask: Task<Void, Never>?
    private var didSetInitialRegion = false
    private let motionEnabled: Bool

    init(
        onSelection: @escaping (Aircraft?) -> Void,
        onAirportSelection: @escaping (Airport?) -> Void,
        onViewport: @escaping (MapBounds) -> Void,
        requestConfiguration: AircraftRequestConfiguration,
        onRenderedSelection: @escaping (Aircraft) -> Void,
        onFollowCancelled: @escaping () -> Void,
        motionEnabled: Bool
    ) {
        self.onSelection = onSelection
        self.onAirportSelection = onAirportSelection
        self.onViewport = onViewport
        self.requestConfiguration = requestConfiguration
        self.onRenderedSelection = onRenderedSelection
        self.onFollowCancelled = onFollowCancelled
        self.motionEnabled = motionEnabled
        motionEngine.interpolationDuration = requestConfiguration.pollingInterval.timeInterval
    }

    isolated deinit { displayLink?.invalidate() }

    func stopRendering() {
        displayLink?.invalidate()
        displayLink = nil
        viewportTask?.cancel()
        viewportTask = nil
        if let trailOverlay { mapView?.removeOverlay(trailOverlay) }
        trailOverlay = nil
        mapView = nil
    }

    func updateSelectionHandler(_ handler: @escaping (Aircraft?) -> Void) { onSelection = handler }
    func updateAirportSelectionHandler(_ handler: @escaping (Airport?) -> Void) { onAirportSelection = handler }
    func updateViewportHandler(_ handler: @escaping (MapBounds) -> Void) { onViewport = handler }

    func updateMotionOptions(
        followsSelectedAircraft: Bool,
        showsSelectedTrail: Bool,
        onRenderedSelection: @escaping (Aircraft) -> Void,
        onFollowCancelled: @escaping () -> Void
    ) {
        self.followsSelectedAircraft = followsSelectedAircraft
        self.showsSelectedTrail = showsSelectedTrail
        self.onRenderedSelection = onRenderedSelection
        self.onFollowCancelled = onFollowCancelled
        updateTrailOverlay()
    }

    func setInitialRegionIfNeeded(on mapView: MKMapView) {
        self.mapView = mapView
        if motionEnabled { startDisplayLinkIfNeeded() }
        guard !didSetInitialRegion else { return }
        didSetInitialRegion = true
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
            span: MKCoordinateSpan(latitudeDelta: 8, longitudeDelta: 9)
        )
        mapView.setRegion(region, animated: false)
        onViewport(MapBounds(region: region, paddingFraction: requestConfiguration.viewportPaddingFraction))
    }

    func apply(
        aircraft newAircraft: [Aircraft],
        airports: [Airport],
        selectedAircraft: Aircraft?,
        selectedAirport: Airport?,
        cameraRequest: MapCameraRequest?,
        to mapView: MKMapView
    ) {
        self.mapView = mapView
        selectedICAO24 = selectedAircraft?.icao24
        selectedAirportID = selectedAirport?.id
        let incoming = Dictionary(uniqueKeysWithValues: newAircraft.map { ($0.icao24, $0) })
        if incoming != lastTargets {
            lastTargets = incoming
            motionEngine.ingest(newAircraft, at: Date())
            diffAnnotations(incoming: incoming, mapView: mapView)
            updateTrailOverlay()
        }
        diffAirports(airports, mapView: mapView)
        synchronizeSelection(selectedAircraft, selectedAirport: selectedAirport, on: mapView)
        applyCameraRequest(cameraRequest, on: mapView)
    }

    private func diffAirports(_ airports: [Airport], mapView: MKMapView) {
        let incoming = Dictionary(uniqueKeysWithValues: airports.map { ($0.id, $0) })
        let incomingKeys = Set(incoming.keys)
        let existingKeys = Set(airportAnnotationsByID.keys)
        let removed = existingKeys.subtracting(incomingKeys).compactMap { airportAnnotationsByID.removeValue(forKey: $0) }
        if !removed.isEmpty { mapView.removeAnnotations(removed) }
        let added = incomingKeys.subtracting(existingKeys).compactMap { id -> AirportAnnotation? in
            guard let airport = incoming[id] else { return nil }
            let annotation = AirportAnnotation(airport: airport)
            airportAnnotationsByID[id] = annotation
            return annotation
        }
        if !added.isEmpty { mapView.addAnnotations(added) }
    }

    private func diffAnnotations(incoming: [String: Aircraft], mapView: MKMapView) {
        let incomingKeys = Set(incoming.keys)
        let existingKeys = Set(annotationsByICAO24.keys)
        let removed = existingKeys.subtracting(incomingKeys).compactMap { annotationsByICAO24.removeValue(forKey: $0) }
        if !removed.isEmpty { mapView.removeAnnotations(removed) }
        let added = incomingKeys.subtracting(existingKeys).compactMap { key -> AircraftAnnotation? in
            guard let aircraft = incoming[key] else { return nil }
            let annotation = AircraftAnnotation(aircraft: aircraft)
            annotationsByICAO24[key] = annotation
            return annotation
        }
        if !added.isEmpty { mapView.addAnnotations(added) }
    }

    private func startDisplayLinkIfNeeded() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(displayFrame(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func displayFrame(_ link: CADisplayLink) {
        guard let mapView else { return }
        let now = Date()
        let rendered = motionEngine.renderedAircraft(at: now)
        for (icao24, aircraft) in rendered {
            guard let annotation = annotationsByICAO24[icao24] else { continue }
            annotation.update(with: aircraft)
            (mapView.view(for: annotation) as? AircraftAnnotationView)?.applyMotion(aircraft)
        }
        guard let selectedICAO24, let selected = rendered[selectedICAO24] else { return }
        if now.timeIntervalSince(lastTelemetryUpdate) >= 0.2 {
            lastTelemetryUpdate = now
            onRenderedSelection(selected)
        }
        if followsSelectedAircraft, now.timeIntervalSince(lastCameraUpdate) >= 0.25 {
            lastCameraUpdate = now
            isProgrammaticCameraChange = true
            mapView.setCenter(selected.coordinate, animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.isProgrammaticCameraChange = false }
        }
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
        if let aircraft = annotation as? AircraftAnnotation {
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: AircraftAnnotationView.reuseIdentifier, for: aircraft) as? AircraftAnnotationView
            view?.annotation = aircraft
            view?.apply(aircraft.aircraft, animated: false)
            return view
        }
        if let airport = annotation as? AirportAnnotation {
            return mapView.dequeueReusableAnnotationView(withIdentifier: AirportAnnotationView.reuseIdentifier, for: airport)
        }
        if annotation is MKClusterAnnotation {
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier, for: annotation) as? MKMarkerAnnotationView
            view?.markerTintColor = .systemIndigo
            view?.glyphImage = UIImage(systemName: "building.2.fill")
            return view
        }
        return nil
    }

    func mapView(_ mapView: MKMapView, didSelect annotation: any MKAnnotation) {
        if let aircraft = annotation as? AircraftAnnotation {
            selectedICAO24 = aircraft.aircraft.icao24
            selectedAirportID = nil
            onAirportSelection(nil)
            onSelection(aircraft.aircraft)
            updateTrailOverlay()
        } else if let airport = annotation as? AirportAnnotation {
            selectedAirportID = airport.airport.id
            selectedICAO24 = nil
            onSelection(nil)
            onAirportSelection(airport.airport)
            updateTrailOverlay()
        }
    }

    func mapView(_ mapView: MKMapView, didDeselect annotation: any MKAnnotation) {
        if annotation is AircraftAnnotation, selectedICAO24 != nil {
            selectedICAO24 = nil
            onSelection(nil)
            updateTrailOverlay()
        } else if annotation is AirportAnnotation, selectedAirportID != nil {
            selectedAirportID = nil
            onAirportSelection(nil)
        }
    }

    func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
        viewportTask?.cancel()
        if !isProgrammaticCameraChange,
           mapView.gestureRecognizers?.contains(where: { $0.state == .began || $0.state == .changed }) == true,
           followsSelectedAircraft {
            followsSelectedAircraft = false
            onFollowCancelled()
        }
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        guard !isProgrammaticCameraChange else { return }
        viewportTask?.cancel()
        let region = mapView.region
        viewportTask = Task { [weak self] in
            do {
                try await Task.sleep(for: self?.requestConfiguration.viewportDebounce ?? .milliseconds(400))
                guard !Task.isCancelled, let self else { return }
                onViewport(MapBounds(region: region, paddingFraction: requestConfiguration.viewportPaddingFraction))
            } catch { return }
        }
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
        guard overlay === trailOverlay else { return MKOverlayRenderer(overlay: overlay) }
        let renderer = MKPolylineRenderer(overlay: overlay)
        renderer.strokeColor = .systemBlue
        renderer.lineWidth = 3
        renderer.alpha = 0.8
        renderer.lineJoin = .round
        return renderer
    }

    private func updateTrailOverlay() {
        guard let mapView else { return }
        guard showsSelectedTrail, let selectedICAO24 else {
            if let trailOverlay { mapView.removeOverlay(trailOverlay) }
            trailOverlay = nil
            trailSignature = []
            return
        }
        let coordinates = motionEngine.trail(for: selectedICAO24).map(\.coordinate)
        guard coordinates.count >= 2, !Self.coordinatesEqual(coordinates, trailSignature) else { return }
        if let trailOverlay { mapView.removeOverlay(trailOverlay) }
        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        mapView.addOverlay(polyline, level: .aboveRoads)
        trailOverlay = polyline
        trailSignature = coordinates
    }

    private func synchronizeSelection(_ selected: Aircraft?, selectedAirport: Airport?, on mapView: MKMapView) {
        let desired: (any MKAnnotation)? = selected.flatMap { annotationsByICAO24[$0.icao24] }
            ?? selectedAirport.flatMap { airportAnnotationsByID[$0.id] }
        let current = mapView.selectedAnnotations.first
        if let desired, current !== desired { mapView.selectAnnotation(desired, animated: true) }
        else if desired == nil, let current { mapView.deselectAnnotation(current, animated: true) }
    }

    private func applyCameraRequest(_ request: MapCameraRequest?, on mapView: MKMapView) {
        guard let request, request.id != lastCameraRequestID else { return }
        lastCameraRequestID = request.id
        isProgrammaticCameraChange = true
        let region = MKCoordinateRegion(
            center: request.coordinate,
            span: MKCoordinateSpan(latitudeDelta: request.latitudeSpan, longitudeDelta: request.latitudeSpan)
        )
        mapView.setRegion(region, animated: !UIAccessibility.isReduceMotionEnabled)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.isProgrammaticCameraChange = false }
    }

    private static func coordinatesEqual(_ lhs: [CLLocationCoordinate2D], _ rhs: [CLLocationCoordinate2D]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy {
            $0.latitude == $1.latitude && $0.longitude == $1.longitude
        }
    }
}
