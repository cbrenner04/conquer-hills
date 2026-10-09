/// A runner-chosen stretch of a course, edited in 0.1 mile steps.
///
/// Boundaries sit on the 0.1 mile grid, except that the end may be the course's exact finish. The range always
/// satisfies `0 ≤ start`, `end ≤ course distance` and `end − start ≥ minimumMeters` (or the whole course, for a
/// course shorter than the minimum). Moving a boundary past what's allowed stops at the limit.
public struct CustomSegmentRange: Equatable, Sendable {
    public static let metersPerMile = 1609.344
    /// Boundaries move in 0.1 mile steps.
    public static let stepMeters = 0.1 * metersPerMile
    /// Custom segments are at least 0.5 mi (about 5 minutes at 6 mph).
    public static let minimumMeters = 0.5 * metersPerMile

    public let courseMeters: Double
    public private(set) var startMeters: Double
    public private(set) var endMeters: Double

    /// The whole course.
    public init(courseMeters: Double) {
        self.courseMeters = courseMeters
        self.startMeters = 0
        self.endMeters = courseMeters
    }

    /// A range starting from the given boundaries, snapped and made valid.
    public init(courseMeters: Double, startMeters: Double, endMeters: Double) {
        self.init(courseMeters: courseMeters)
        self.endMeters = clampEnd(snap(endMeters), start: 0)
        self.startMeters = clampStart(snap(startMeters), end: self.endMeters)
        self.endMeters = clampEnd(self.endMeters, start: self.startMeters)
    }

    public var distanceMeters: Double { endMeters - startMeters }

    /// Moves the start by a number of 0.1 mile steps (negative moves it earlier).
    public mutating func moveStart(bySteps steps: Int) {
        startMeters = clampStart(snap(startMeters + Double(steps) * Self.stepMeters), end: endMeters)
    }

    /// Moves the end by a number of 0.1 mile steps (negative moves it earlier).
    public mutating func moveEnd(bySteps steps: Int) {
        endMeters = clampEnd(snap(endMeters + Double(steps) * Self.stepMeters), start: startMeters)
    }

    public var canMoveStartEarlier: Bool { startMeters > 0 }
    public var canMoveStartLater: Bool { startMeters < latestStart(end: endMeters) - 1e-6 }
    public var canMoveEndEarlier: Bool { endMeters > earliestEnd(start: startMeters) + 1e-6 }
    public var canMoveEndLater: Bool { endMeters < courseMeters - 1e-6 }

    /// The custom segment for this range.
    public func segment(in course: Course) -> CourseSegment? {
        course.customSegment(startMeters: startMeters, endMeters: endMeters)
    }

    // MARK: Rules

    /// Nearest 0.1 mile, or the exact finish when within half a step of it.
    private func snap(_ meters: Double) -> Double {
        if abs(courseMeters - meters) < Self.stepMeters / 2 { return courseMeters }
        return (meters / Self.stepMeters).rounded() * Self.stepMeters
    }

    private var minimumLength: Double { min(Self.minimumMeters, courseMeters) }

    private func latestStart(end: Double) -> Double {
        // The latest grid point leaving at least the minimum before `end`.
        max(0, ((end - minimumLength) / Self.stepMeters + 1e-9).rounded(.down) * Self.stepMeters)
    }

    private func earliestEnd(start: Double) -> Double {
        let earliest = ((start + minimumLength) / Self.stepMeters - 1e-9).rounded(.up) * Self.stepMeters
        return min(earliest, courseMeters)
    }

    private func clampStart(_ start: Double, end: Double) -> Double {
        min(max(start, 0), latestStart(end: end))
    }

    private func clampEnd(_ end: Double, start: Double) -> Double {
        min(max(end, earliestEnd(start: start)), courseMeters)
    }
}

/// Elevation data shaped for charts: downsampled and sliced, still in meters.
public enum ElevationChartData {
    /// At most about `maximumPoints` samples, keeping the first and last and each bucket's lowest and highest
    /// points (in distance order), so peaks and dips survive downsampling.
    public static func downsample(_ samples: [ElevationSample], maximumPoints: Int) -> [ElevationSample] {
        guard samples.count > maximumPoints, maximumPoints >= 4 else { return samples }
        let interior = samples.dropFirst().dropLast()
        let buckets = max(1, (maximumPoints - 2) / 2)
        let bucketSize = Double(interior.count) / Double(buckets)
        var result = [samples[0]]
        for bucket in 0..<buckets {
            let lower = interior.startIndex + Int((Double(bucket) * bucketSize).rounded(.down))
            let upper = min(
                interior.startIndex + Int((Double(bucket + 1) * bucketSize).rounded(.down)), interior.endIndex)
            guard lower < upper else { continue }
            let slice = samples[lower..<upper]
            guard let low = slice.min(by: { $0.elevationMeters < $1.elevationMeters }),
                let high = slice.max(by: { $0.elevationMeters < $1.elevationMeters })
            else { continue }
            if low.distanceMeters == high.distanceMeters {
                result.append(low)
            } else {
                result += low.distanceMeters < high.distanceMeters ? [low, high] : [high, low]
            }
        }
        result.append(samples[samples.count - 1])
        return result
    }

    /// The samples between two course positions, with interpolated samples added exactly at both ends.
    public static func slice(_ samples: [ElevationSample], from start: Double, to end: Double) -> [ElevationSample] {
        guard start < end, !samples.isEmpty else { return [] }
        var result = [ElevationSample(distanceMeters: start, elevationMeters: elevation(at: start, in: samples))]
        result += samples.filter { $0.distanceMeters > start && $0.distanceMeters < end }
        result.append(ElevationSample(distanceMeters: end, elevationMeters: elevation(at: end, in: samples)))
        return result
    }

    /// Linearly interpolated elevation at a course position, clamped to the first and last samples.
    public static func elevation(at distance: Double, in samples: [ElevationSample]) -> Double {
        guard let first = samples.first, let last = samples.last else { return 0 }
        if distance <= first.distanceMeters { return first.elevationMeters }
        if distance >= last.distanceMeters { return last.elevationMeters }
        let upper = samples.firstIndex { $0.distanceMeters >= distance } ?? samples.count - 1
        let a = samples[upper - 1]
        let b = samples[upper]
        let t = (distance - a.distanceMeters) / (b.distanceMeters - a.distanceMeters)
        return a.elevationMeters + t * (b.elevationMeters - a.elevationMeters)
    }
}
