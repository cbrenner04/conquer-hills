import Foundation

/// Authored elevation control points for structures bare-earth elevation data can't see, such as bridge decks:
/// `profiles.json`.
///
/// Bare-earth data removes bridges, so the build normally interpolates straight across them. Where a bridge is a
/// real climb, a profile gives its deck elevations instead, from a cited source. Points are stored by position, not
/// course distance, so they survive changes to calibration.
public struct ProfilesFile: Codable, Equatable, Sendable {
    public struct Profile: Codable, Equatable, Sendable {
        public var name: String
        /// Where the elevations come from (a citation).
        public var source: String
        /// How they were derived.
        public var method: String
        /// In course order, from where the structure leaves the ground to where it rejoins it.
        public var points: [Point]

        public init(name: String, source: String, method: String, points: [Point]) {
            self.name = name
            self.source = source
            self.method = method
            self.points = points
        }
    }

    /// A control point: an absolute elevation, or a rise above the straight line between the profile's ends (for
    /// modelled humps). Exactly one of the two is set.
    public struct Point: Codable, Equatable, Sendable {
        public var latitude: Double
        public var longitude: Double
        public var elevationMeters: Double?
        public var riseMeters: Double?

        public init(latitude: Double, longitude: Double, elevationMeters: Double? = nil, riseMeters: Double? = nil) {
            self.latitude = latitude
            self.longitude = longitude
            self.elevationMeters = elevationMeters
            self.riseMeters = riseMeters
        }

        var location: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }
    }

    /// In course order.
    public var profiles: [Profile]

    public init(profiles: [Profile]) {
        self.profiles = profiles
    }
}

/// A profile applied to the course, for the review report.
public struct ProfileSpan: Equatable, Sendable {
    public var name: String
    public var source: String
    /// Official course distance of the first and last control points.
    public var startMeters: Double
    public var endMeters: Double
    /// Official course distance and elevation of each control point.
    public var controlPoints: [(meters: Double, elevationMeters: Double)]

    public static func == (lhs: ProfileSpan, rhs: ProfileSpan) -> Bool {
        lhs.name == rhs.name && lhs.source == rhs.source && lhs.startMeters == rhs.startMeters
            && lhs.endMeters == rhs.endMeters
            && lhs.controlPoints.elementsEqual(rhs.controlPoints) { $0 == $1 }
    }
}

public enum DeckProfiles {
    /// A control point farther than this from the route means it was placed on the wrong road.
    public static let maximumOffRouteMeters = 30.0

    /// Each control point's distance along the measured route (raw meters), found in order: every point after the
    /// previous one, every profile after the previous profile, so a structure crossed twice resolves to the right
    /// pass. Points only match stretches of route heading the profile's way at that point (from the point before it
    /// to the point after), so on an out-and-back along a divided road, a bridge's return carriageway isn't matched
    /// on the way out.
    public static func locate(
        _ profiles: [ProfilesFile.Profile], samples: [ElevationSamplesFile.Sample]
    ) throws -> [[Double]] {
        guard samples.count >= 2 else { throw PipelineError("too few samples to place profiles") }
        let projection = Geo.Projection(fitting: samples.map(\.location))
        let line = samples.map { projection.point($0.location) }
        var searchFrom = 0
        var previousRaw = -Double.infinity
        return try profiles.map { profile in
            guard profile.points.count >= 2 else {
                throw PipelineError("profile \"\(profile.name)\" needs at least two points")
            }
            let located = profile.points.map { projection.point($0.location) }
            return try profile.points.enumerated().map { number, point in
                // The profile's own direction at this point, from the point before it to the point after.
                let before = located[max(number - 1, 0)]
                let after = located[min(number + 1, located.count - 1)]
                let heading = (x: after.x - before.x, y: after.y - before.y)
                guard (point.elevationMeters == nil) != (point.riseMeters == nil) else {
                    throw PipelineError(
                        "profile \"\(profile.name)\" point \(number + 1) needs exactly one of elevationMeters and "
                            + "riseMeters")
                }
                let p = projection.point(point.location)
                var best: (segment: Int, t: Double, distance: Double)?
                var segment = searchFrom
                while segment < line.count - 1 {
                    let (t, d) = RouteGraph.project(p, line[segment], line[segment + 1])
                    let along =
                        (line[segment + 1].x - line[segment].x) * heading.x
                        + (line[segment + 1].y - line[segment].y) * heading.y
                    if d <= maximumOffRouteMeters, along >= 0 {
                        if best == nil || d < best!.distance { best = (segment, t, d) }
                    } else if best != nil {
                        break
                    }
                    segment += 1
                }
                guard let best else {
                    throw PipelineError(
                        "profile \"\(profile.name)\" point \(number + 1) is not within \(Int(maximumOffRouteMeters)) m "
                            + "of the route after the previous point")
                }
                let a = samples[best.segment].distanceMeters
                let b = samples[best.segment + 1].distanceMeters
                let raw = a + best.t * (b - a)
                guard raw > previousRaw else {
                    throw PipelineError("profile \"\(profile.name)\" point \(number + 1) is out of course order")
                }
                previousRaw = raw
                searchFrom = best.segment
                return raw
            }
        }
    }

    /// The elevation each profiled sample takes (by sample index), and the spans for the report.
    ///
    /// `rawDistances` are the samples' distances along the measured route; `base` is the cleaned elevation of every
    /// sample without profiles, which `riseMeters` points are measured from.
    public static func resolve(
        _ profiles: [ProfilesFile.Profile], located: [[Double]], rawDistances: [Double], base: [Double],
        official: (Double) -> Double
    ) throws -> (fixed: [Int: Double], spans: [ProfileSpan]) {
        func interpolate(_ xs: [Double], _ ys: [Double], at x: Double) -> Double {
            guard x > xs[0] else { return ys[0] }
            guard x < xs[xs.count - 1] else { return ys[ys.count - 1] }
            let i = xs.lastIndex { $0 <= x }!
            return ys[i] + (x - xs[i]) / (xs[i + 1] - xs[i]) * (ys[i + 1] - ys[i])
        }
        var fixed: [Int: Double] = [:]
        var spans: [ProfileSpan] = []
        for (profile, raws) in zip(profiles, located) {
            guard let last = raws.last, last <= rawDistances[rawDistances.count - 1] else {
                throw PipelineError("profile \"\(profile.name)\" runs past the finish")
            }
            let startBase = interpolate(rawDistances, base, at: raws[0])
            let endBase = interpolate(rawDistances, base, at: last)
            let elevations = zip(profile.points, raws).map { point, raw in
                point.elevationMeters
                    ?? startBase + (raw - raws[0]) / (last - raws[0]) * (endBase - startBase) + point.riseMeters!
            }
            for (i, raw) in rawDistances.enumerated() where raw >= raws[0] && raw <= last {
                fixed[i] = interpolate(raws, elevations, at: raw)
            }
            spans.append(
                ProfileSpan(
                    name: profile.name, source: profile.source, startMeters: official(raws[0]),
                    endMeters: official(last), controlPoints: zip(raws, elevations).map { (official($0), $1) }))
        }
        return (fixed, spans)
    }
}
