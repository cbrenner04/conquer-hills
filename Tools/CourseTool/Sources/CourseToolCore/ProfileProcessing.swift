import Foundation

/// An elevation series along the course: distances (strictly increasing) and elevations.
public struct ElevationSeries: Equatable, Sendable {
    public var distances: [Double]
    public var elevations: [Double]

    public init(distances: [Double], elevations: [Double]) {
        precondition(distances.count == elevations.count && !distances.isEmpty)
        self.distances = distances
        self.elevations = elevations
    }

    /// Elevation at any distance, by linear interpolation (clamped at the ends).
    public func elevation(at d: Double) -> Double {
        if d <= distances[0] { return elevations[0] }
        if d >= distances[distances.count - 1] { return elevations[elevations.count - 1] }
        var lo = 0
        var hi = distances.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if distances[mid] <= d { lo = mid } else { hi = mid }
        }
        let t = (d - distances[lo]) / (distances[hi] - distances[lo])
        return elevations[lo] + t * (elevations[hi] - elevations[lo])
    }

    /// Centred moving average over `windowMeters`. Near the ends the window shrinks symmetrically, so a constant
    /// grade passes through unchanged.
    public func smoothed(windowMeters: Double) -> ElevationSeries {
        guard windowMeters > 0 else { return self }
        var prefix = [0.0]
        for e in elevations { prefix.append(prefix[prefix.count - 1] + e) }
        let start = distances[0]
        let end = distances[distances.count - 1]
        let result = distances.indices.map { i in
            let half = min(windowMeters / 2, distances[i] - start, end - distances[i])
            let lo = firstIndex(atOrAfter: distances[i] - half - 1e-9)
            let hi = firstIndex(atOrAfter: distances[i] + half + 1e-9) - 1
            return (prefix[hi + 1] - prefix[lo]) / Double(hi - lo + 1)
        }
        return ElevationSeries(distances: distances, elevations: result)
    }

    /// Index of the first distance ≥ `d` (or `count` if none).
    private func firstIndex(atOrAfter d: Double) -> Int {
        var lo = 0
        var hi = distances.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if distances[mid] < d { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// Total climb and descent, summed over consecutive samples.
    public var gainAndLoss: (gain: Double, loss: Double) {
        var gain = 0.0
        var loss = 0.0
        for (a, b) in zip(elevations, elevations.dropFirst()) {
            if b > a { gain += b - a } else { loss += a - b }
        }
        return (gain, loss)
    }
}

/// A stretch with one course incline.
public struct InclineInterval: Equatable, Sendable {
    public var startMeters: Double
    public var endMeters: Double
    public var inclinePercent: Double
    public var length: Double { endMeters - startMeters }
}

public enum InclineIntervals {
    /// Rounds to the nearest multiple of `step`, half away from zero, never producing -0.
    static func round(_ value: Double, step: Double) -> Double {
        let r = (value / step).rounded(.toNearestOrAwayFromZero) * step
        return r == 0 ? 0 : r
    }

    /// Course incline intervals from a (smoothed) elevation series.
    ///
    /// Grade is averaged over fixed blocks and rounded to `step`; equal neighbours merge. Then, while any interval
    /// is shorter than `minimum`, the shortest is merged into whichever neighbour has the closer incline, and the
    /// merged incline is recomputed from its net rise over its length, so merging preserves net elevation.
    public static func build(
        series: ElevationSeries, totalMeters: Double, blockMeters: Double, minimumMeters: Double, step: Double
    ) -> [InclineInterval] {
        func incline(_ a: Double, _ b: Double) -> Double {
            round((series.elevation(at: b) - series.elevation(at: a)) / (b - a) * 100, step: step)
        }
        var boundaries = Array(stride(from: 0, to: totalMeters, by: blockMeters))
        // A final sliver shorter than half a block joins the block before it.
        if boundaries.count > 1, totalMeters - boundaries[boundaries.count - 1] < blockMeters / 2 {
            boundaries.removeLast()
        }
        boundaries.append(totalMeters)
        var intervals = zip(boundaries, boundaries.dropFirst()).map {
            InclineInterval(startMeters: $0, endMeters: $1, inclinePercent: incline($0, $1))
        }
        intervals = mergeEqualNeighbours(intervals)

        while intervals.count > 1,
            let shortest = intervals.indices.min(by: { intervals[$0].length < intervals[$1].length }),
            intervals[shortest].length < minimumMeters - 1e-9
        {
            let current = intervals[shortest]
            let neighbour: Int
            if shortest == 0 {
                neighbour = 1
            } else if shortest == intervals.count - 1 {
                neighbour = shortest - 1
            } else {
                let left = abs(intervals[shortest - 1].inclinePercent - current.inclinePercent)
                let right = abs(intervals[shortest + 1].inclinePercent - current.inclinePercent)
                neighbour = right < left ? shortest + 1 : shortest - 1
            }
            let first = min(shortest, neighbour)
            let start = intervals[first].startMeters
            let end = intervals[first + 1].endMeters
            intervals.replaceSubrange(
                first...(first + 1),
                with: [InclineInterval(startMeters: start, endMeters: end, inclinePercent: incline(start, end))])
            intervals = mergeEqualNeighbours(intervals)
        }
        return intervals
    }

    static func mergeEqualNeighbours(_ intervals: [InclineInterval]) -> [InclineInterval] {
        var result: [InclineInterval] = []
        for interval in intervals {
            if let last = result.last, last.inclinePercent == interval.inclinePercent {
                result[result.count - 1].endMeters = interval.endMeters
            } else {
                result.append(interval)
            }
        }
        return result
    }
}
