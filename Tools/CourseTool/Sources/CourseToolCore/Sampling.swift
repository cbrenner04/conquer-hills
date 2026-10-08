import Foundation

/// Turns route geometry into the line distances are measured along and the points elevation is looked up at.
public enum RouteSampling {
    /// The route as measured: the routed line smoothed toward the racing line (see `Geo.smoothLine`).
    public static func measuredLine(route: [Coordinate], smoothingMeters: Double) -> (
        points: [Geo.Point], projection: Geo.Projection
    ) {
        let projection = Geo.Projection(fitting: route)
        return (Geo.smoothLine(route.map(projection.point), windowMeters: smoothingMeters), projection)
    }

    /// Empty samples every `spacing` meters along the measured line, plus one at the end.
    public static func samples(route: [Coordinate], smoothingMeters: Double, spacing: Double)
        -> [ElevationSamplesFile.Sample]
    {
        let (line, projection) = measuredLine(route: route, smoothingMeters: smoothingMeters)
        let points = Geo.resample(line, every: spacing)
        let distances = Geo.cumulativeDistances(points)
        return zip(points, distances).map { point, distance in
            let c = projection.coordinate(point)
            return ElevationSamplesFile.Sample(
                distanceMeters: roundTo(distance, places: 2),
                location: Coordinate(
                    latitude: roundTo(c.latitude, places: 7), longitude: roundTo(c.longitude, places: 7)),
                elevationMeters: nil, source: nil)
        }
    }

    /// Fingerprint of the route plus the settings that determine sample positions.
    public static func fingerprint(route: [Coordinate], smoothingMeters: Double, spacing: Double) -> String {
        let text =
            route.map { "\(roundTo($0.latitude, places: 7)),\(roundTo($0.longitude, places: 7))" }
            .joined(separator: ";") + "|\(smoothingMeters)|\(spacing)"
        return CourseToolCore.fingerprint(text)
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
        return ElevationSamplesFile(
            provider: provider, routeFingerprint: print, routeSmoothingMeters: smoothingMeters,
            sampleSpacingMeters: spacing, fetchedOn: nil,
            samples: samples(route: route, smoothingMeters: smoothingMeters, spacing: spacing))
    }
}
