import CoreLocation
import Foundation
import OSLog

struct AircraftMotionEngine: Sendable {
    struct Transition: Sendable {
        let start: Aircraft
        let target: Aircraft
        let startedAt: Date
        let duration: TimeInterval
        let shouldInterpolate: Bool
    }

    var interpolationDuration: TimeInterval = 10
    var maximumJumpMeters = 200_000.0
    private(set) var transitions: [String: Transition] = [:]
    private(set) var trails = AircraftTrailStore()
    private let logger = Logger(subsystem: "com.example.FlightTracker", category: "Motion")

    mutating func ingest(_ aircraft: [Aircraft], at now: Date) {
        let incomingIDs = Set(aircraft.map(\.icao24))
        transitions = transitions.filter { incomingIDs.contains($0.key) }
        for target in aircraft {
            let previous = renderedAircraft(icao24: target.icao24, at: now) ?? target
            let reasonable = Self.isReasonableTransition(from: previous, to: target, maximumJumpMeters: maximumJumpMeters)
            if !reasonable { logger.warning("Snapping unreasonable movement for \(target.icao24, privacy: .public)") }
            transitions[target.icao24] = Transition(
                start: previous,
                target: target,
                startedAt: now,
                duration: interpolationDuration,
                shouldInterpolate: reasonable
            )
            trails.append(
                AircraftTrailPoint(
                    coordinate: target.coordinate,
                    altitude: target.barometricAltitudeMeters,
                    timestamp: target.positionTimestamp ?? target.lastContact
                ),
                icao24: target.icao24,
                now: now
            )
        }
        trails.purge(activeICAO24: incomingIDs, now: now)
    }

    func renderedAircraft(at date: Date) -> [String: Aircraft] {
        Dictionary(uniqueKeysWithValues: transitions.compactMap { key, _ in
            renderedAircraft(icao24: key, at: date).map { (key, $0) }
        })
    }

    func renderedAircraft(icao24: String, at date: Date) -> Aircraft? {
        guard let transition = transitions[icao24] else { return nil }
        guard transition.shouldInterpolate, transition.duration > 0 else { return transition.target }
        let progress = min(1, max(0, date.timeIntervalSince(transition.startedAt) / transition.duration))
        return Self.interpolate(from: transition.start, to: transition.target, progress: progress)
    }

    func trail(for icao24: String) -> [AircraftTrailPoint] { trails.points(for: icao24) }

    static func interpolate(from start: Aircraft, to target: Aircraft, progress: Double) -> Aircraft {
        let t = min(1, max(0, progress))
        var aircraft = target
        aircraft.coordinate.latitude = start.coordinate.latitude + (target.coordinate.latitude - start.coordinate.latitude) * t
        var longitudeDelta = target.coordinate.longitude - start.coordinate.longitude
        if longitudeDelta > 180 { longitudeDelta -= 360 }
        if longitudeDelta < -180 { longitudeDelta += 360 }
        aircraft.coordinate.longitude = MapBounds.normalizeLongitude(start.coordinate.longitude + longitudeDelta * t)
        if let startHeading = start.headingDegrees, let targetHeading = target.headingDegrees {
            var delta = (targetHeading - startHeading).truncatingRemainder(dividingBy: 360)
            if delta > 180 { delta -= 360 }
            if delta < -180 { delta += 360 }
            var heading = (startHeading + delta * t).truncatingRemainder(dividingBy: 360)
            if heading < 0 { heading += 360 }
            aircraft.headingDegrees = heading
        }
        if let startAltitude = start.barometricAltitudeMeters, let targetAltitude = target.barometricAltitudeMeters {
            aircraft.barometricAltitudeMeters = startAltitude + (targetAltitude - startAltitude) * t
        }
        return aircraft
    }

    static func isReasonableTransition(from start: Aircraft, to target: Aircraft, maximumJumpMeters: Double) -> Bool {
        guard target.lastContact >= start.lastContact,
              (-90...90).contains(target.coordinate.latitude),
              (-180...180).contains(target.coordinate.longitude) else { return false }
        let distance = CLLocation(latitude: start.coordinate.latitude, longitude: start.coordinate.longitude)
            .distance(from: CLLocation(latitude: target.coordinate.latitude, longitude: target.coordinate.longitude))
        let elapsed = max(1, target.lastContact.timeIntervalSince(start.lastContact))
        let plausible = max(maximumJumpMeters, (target.groundSpeedMetersPerSecond ?? 300) * elapsed * 4)
        return distance <= plausible
    }
}
