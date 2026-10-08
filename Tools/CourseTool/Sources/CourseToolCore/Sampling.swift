import Foundation

/// Turns the stored route into the line distances are measured along and the points elevation is looked up at.
///
/// Sample positions are not stored: they are recomputed here, deterministically, from the stored (rounded) route
/// and the config, by every step that needs them.
public enum RouteSampling {
    /// One sample point: distance along the measured line (before calibration) and its position.
    public struct Position: Equatable, Sendable {
        public var distanceMeters: Double
        public var location: Coordinate
    }

    /// The route as measured: the routed line smoothed toward the racing line (see `Geo.smoothLine`).
    public static func measuredLine(route: [Coordinate], smoothingMeters: Double) -> (
        points: [Geo.Point], projection: Geo.Projection
    ) {
        let projection = Geo.Projection(fitting: route)
        return (Geo.smoothLine(route.map(projection.point), windowMeters: smoothingMeters), projection)
    }

    /// A position every `spacing` meters along the measured line, plus one at the end.
    public static func positions(route: [Coordinate], smoothingMeters: Double, spacing: Double) -> [Position] {
        let (line, projection) = measuredLine(route: route, smoothingMeters: smoothingMeters)
        let points = Geo.resample(line, every: spacing)
        let distances = Geo.cumulativeDistances(points)
        return zip(points, distances).map { Position(distanceMeters: $1, location: projection.coordinate($0)) }
    }

    /// Fingerprint of the route plus the settings that determine sample positions.
    public static func fingerprint(route: [Coordinate], smoothingMeters: Double, spacing: Double) -> String {
        CourseToolCore.fingerprint(Polyline.encode(route) + "|\(smoothingMeters)|\(spacing)")
    }

    /// Prepares the samples file for `route`: reuses already-fetched values if the route and settings are
    /// unchanged, otherwise starts fresh.
    public static func prepare(
        existing: ElevationSamplesFile?, route: [Coordinate], provider: String, smoothingMeters: Double,
        spacing: Double
    ) -> ElevationSamplesFile {
        let print = fingerprint(route: route, smoothingMeters: smoothingMeters, spacing: spacing)
        if let existing, existing.routeFingerprint == print, existing.provider == provider {
            return existing
        }
        let count = positions(route: route, smoothingMeters: smoothingMeters, spacing: spacing).count
        return ElevationSamplesFile(
            provider: provider, routeFingerprint: print, routeSmoothingMeters: smoothingMeters,
            sampleSpacingMeters: spacing, count: count)
    }
}

/// Projects OSM bridges, tunnels and covered ways onto the route, as distance ranges. Done once, by the `route`
/// step; the build only reads the ranges.
public enum StructureSpans {
    /// An OSM way as returned by Overpass.
    public struct Way: Equatable, Sendable {
        public var id: Int
        public var tags: [String: String]
        public var geometry: [Coordinate]

        public init(id: Int, tags: [String: String], geometry: [Coordinate]) {
            self.id = id
            self.tags = tags
            self.geometry = geometry
        }
    }

    /// The stretches of route each way runs along: sample positions within the buffer of the way, where the way
    /// runs within the maximum angle of the route's direction (so bridges crossing over the route don't count).
    ///
    /// Only ways that can carry the route count: they need an OSM `highway` tag not in `ignoredHighways`, and
    /// tunnels and covered ways in `ignoredTunnelHighways` (underground concourses, arcades) are skipped.
    public static func compute(
        ways: [Way], positions: [RouteSampling.Position], settings: CourseConfig.StructureSettings
    ) -> [StructuresFile.Span] {
        let bufferMeters = settings.bufferMeters
        let maximumAngleDegrees = settings.maximumAngleDegrees
        let projection = Geo.Projection(fitting: positions.map(\.location))
        let points = positions.map { projection.point($0.location) }
        var spans: [StructuresFile.Span] = []
        for way in ways {
            guard let highway = way.tags["highway"], !settings.ignoredHighways.contains(highway) else { continue }
            let kind =
                way.tags["bridge"].map { $0 != "no" } == true
                ? "bridge" : way.tags["tunnel"].map { $0 != "no" } == true ? "tunnel" : "covered"
            if kind != "bridge" && settings.ignoredTunnelHighways.contains(highway) { continue }
            let wayPoints = way.geometry.map(projection.point)
            var runStart: Int?
            for i in points.indices {
                let on = runs(
                    along: wayPoints, at: i, points: points, buffer: bufferMeters, maxAngle: maximumAngleDegrees)
                if on, runStart == nil { runStart = i }
                if !on || i == points.count - 1, let start = runStart {
                    let end = on ? i : i - 1
                    spans.append(
                        StructuresFile.Span(
                            kind: kind, osmWayId: way.id, name: way.tags["name"], highway: highway,
                            startMeters: roundTo(positions[start].distanceMeters, places: 2),
                            endMeters: roundTo(positions[end].distanceMeters, places: 2)))
                    runStart = nil
                }
            }
        }
        return spans
    }

    /// Whether the route at point `i` runs along the way.
    static func runs(along way: [Geo.Point], at i: Int, points: [Geo.Point], buffer: Double, maxAngle: Double) -> Bool {
        let p = points[i]
        let before = points[max(0, i - 2)]
        let after = points[min(points.count - 1, i + 2)]
        let routeAngle = atan2(after.y - before.y, after.x - before.x)
        for (a, b) in zip(way, way.dropFirst()) where Geo.distanceToSegment(p, a, b) <= buffer {
            var difference = abs(atan2(b.y - a.y, b.x - a.x) - routeAngle).truncatingRemainder(dividingBy: .pi)
            difference = min(difference, .pi - difference)
            if difference * 180 / .pi <= maxAngle { return true }
        }
        return false
    }
}
