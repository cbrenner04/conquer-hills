import Foundation

/// A WGS84 position.
public struct Coordinate: Codable, Equatable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Geometry helpers. Routes are a few tens of kilometres across, so after a great-circle check this works on a
/// local flat projection centred on the route; over 40 km the error is well under 0.1%, which the checkpoint
/// calibration absorbs anyway.
public enum Geo {
    public static let earthRadiusMeters = 6_371_008.8

    /// Great-circle distance in meters.
    public static func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusMeters * asin(min(1, sqrt(h)))
    }

    /// Equirectangular projection to meters around a reference latitude.
    public struct Projection: Sendable {
        public let referenceLatitude: Double
        let metersPerDegreeLatitude: Double
        let metersPerDegreeLongitude: Double

        public init(referenceLatitude: Double) {
            self.referenceLatitude = referenceLatitude
            metersPerDegreeLatitude = Geo.earthRadiusMeters * .pi / 180
            metersPerDegreeLongitude = metersPerDegreeLatitude * cos(referenceLatitude * .pi / 180)
        }

        /// A projection centred on the mean latitude of `points`.
        public init(fitting points: [Coordinate]) {
            let mean = points.isEmpty ? 0 : points.map(\.latitude).reduce(0, +) / Double(points.count)
            self.init(referenceLatitude: mean)
        }

        public func point(_ c: Coordinate) -> Point {
            Point(x: c.longitude * metersPerDegreeLongitude, y: c.latitude * metersPerDegreeLatitude)
        }

        public func coordinate(_ p: Point) -> Coordinate {
            Coordinate(latitude: p.y / metersPerDegreeLatitude, longitude: p.x / metersPerDegreeLongitude)
        }
    }

    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }

        func distance(to other: Point) -> Double { hypot(other.x - x, other.y - y) }
    }

    /// Points every `step` meters along a polyline, starting at its first point and ending at its last.
    public static func resample(_ line: [Point], every step: Double) -> [Point] {
        precondition(step > 0)
        guard let first = line.first else { return [] }
        var result = [first]
        var untilNext = step
        for (a, b) in zip(line, line.dropFirst()) {
            let length = a.distance(to: b)
            guard length > 0 else { continue }
            var position = untilNext
            while position <= length {
                let t = position / length
                result.append(Point(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                position += step
            }
            untilNext = position - length
        }
        if let last = line.last, result.last.map({ $0.distance(to: last) > 1e-6 }) ?? true {
            result.append(last)
        }
        return result
    }

    /// Smooths a polyline with a centred moving average over `windowMeters`, after resampling every 5 m.
    ///
    /// Routers in dense cities follow separately mapped sidewalks and zigzag through every junction. Averaging
    /// positions flattens those zigzags and slightly rounds corners, approximating the racing line along which
    /// road courses are measured. The end points are kept exactly. A window of 0 returns the 5 m resampling.
    public static func smoothLine(_ line: [Point], windowMeters: Double) -> [Point] {
        let step = 5.0
        let dense = resample(line, every: step)
        let half = Int((windowMeters / 2 / step).rounded())
        guard half > 0, dense.count > 2 else { return dense }
        var smoothed = dense
        var sumX = 0.0
        var sumY = 0.0
        // Prefix sums keep this linear in the number of points.
        var prefixX = [0.0]
        var prefixY = [0.0]
        for p in dense {
            sumX += p.x
            sumY += p.y
            prefixX.append(sumX)
            prefixY.append(sumY)
        }
        for i in 1..<(dense.count - 1) {
            let w = min(half, i, dense.count - 1 - i)  // symmetric window near the ends
            let lo = i - w
            let hi = i + w + 1
            let n = Double(hi - lo)
            smoothed[i] = Point(x: (prefixX[hi] - prefixX[lo]) / n, y: (prefixY[hi] - prefixY[lo]) / n)
        }
        return smoothed
    }

    /// Cumulative distance along a polyline, starting at 0.
    public static func cumulativeDistances(_ line: [Point]) -> [Double] {
        var result = [0.0]
        result.reserveCapacity(line.count)
        for (a, b) in zip(line, line.dropFirst()) {
            result.append(result[result.count - 1] + a.distance(to: b))
        }
        return result
    }

    /// Distance from `p` to the segment `a`–`b`, and the segment's direction (radians, mod π).
    static func distanceToSegment(_ p: Point, _ a: Point, _ b: Point) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return p.distance(to: a) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return p.distance(to: Point(x: a.x + t * dx, y: a.y + t * dy))
    }

    /// Simplifies a polyline with Douglas–Peucker; used only to keep network queries short.
    public static func simplify(_ line: [Point], toleranceMeters: Double) -> [Point] {
        guard line.count > 2 else { return line }
        var keep = [Bool](repeating: false, count: line.count)
        keep[0] = true
        keep[line.count - 1] = true
        var stack = [(0, line.count - 1)]
        while let (start, end) = stack.popLast() {
            var farthest = -1.0
            var index = -1
            for k in (start + 1)..<end {
                let d = distanceToSegment(line[k], line[start], line[end])
                if d > farthest {
                    farthest = d
                    index = k
                }
            }
            if farthest > toleranceMeters, index > 0 {
                keep[index] = true
                stack.append((start, index))
                stack.append((index, end))
            }
        }
        return zip(line, keep).compactMap { $1 ? $0 : nil }
    }
}
