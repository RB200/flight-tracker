import MapKit

struct AircraftTrailStore: Sendable {
    var maximumAge: TimeInterval = 30 * 60
    var maximumPoints = 600
    var simplificationThreshold = 200
    var simplificationToleranceMeters = 35.0
    private(set) var pointsByICAO24: [String: [AircraftTrailPoint]] = [:]

    mutating func append(_ point: AircraftTrailPoint, icao24: String, now: Date) {
        var points = pointsByICAO24[icao24, default: []]
        if let last = points.last {
            guard point.timestamp >= last.timestamp else { return }
            if last.coordinate.latitude == point.coordinate.latitude,
               last.coordinate.longitude == point.coordinate.longitude { return }
        }
        points.append(point)
        let cutoff = now.addingTimeInterval(-maximumAge)
        points.removeAll { $0.timestamp < cutoff }
        if points.count > simplificationThreshold {
            points = Self.simplify(points, toleranceMeters: simplificationToleranceMeters)
        }
        if points.count > maximumPoints {
            points.removeFirst(points.count - maximumPoints)
        }
        pointsByICAO24[icao24] = points
    }

    mutating func purge(activeICAO24: Set<String>, now: Date) {
        let cutoff = now.addingTimeInterval(-maximumAge)
        for key in pointsByICAO24.keys {
            pointsByICAO24[key]?.removeAll { $0.timestamp < cutoff }
            if pointsByICAO24[key]?.isEmpty == true { pointsByICAO24[key] = nil }
        }
        _ = activeICAO24
    }

    func points(for icao24: String) -> [AircraftTrailPoint] {
        pointsByICAO24[icao24] ?? []
    }

    static func simplify(_ points: [AircraftTrailPoint], toleranceMeters: Double) -> [AircraftTrailPoint] {
        guard points.count > 2 else { return points }
        let mapPoints = points.map { MKMapPoint($0.coordinate) }
        var keep = Set([0, points.count - 1])

        func reduce(_ first: Int, _ last: Int) {
            guard last > first + 1 else { return }
            var greatestDistance = 0.0
            var greatestIndex = first
            for index in (first + 1)..<last {
                let distance = perpendicularDistance(mapPoints[index], mapPoints[first], mapPoints[last])
                if distance > greatestDistance { greatestDistance = distance; greatestIndex = index }
            }
            if greatestDistance > toleranceMeters {
                keep.insert(greatestIndex)
                reduce(first, greatestIndex)
                reduce(greatestIndex, last)
            }
        }

        reduce(0, points.count - 1)
        return keep.sorted().map { points[$0] }
    }

    private static func perpendicularDistance(_ point: MKMapPoint, _ start: MKMapPoint, _ end: MKMapPoint) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard dx != 0 || dy != 0 else { return point.distance(to: start) }
        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / (dx * dx + dy * dy)))
        return point.distance(to: MKMapPoint(x: start.x + t * dx, y: start.y + t * dy))
    }
}
