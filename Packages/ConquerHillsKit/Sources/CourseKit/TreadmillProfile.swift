/// How course incline is turned into treadmill incline: a baseline offset, the treadmill's limits, and the step
/// size of its incline control.
public struct TreadmillSettings: Equatable, Sendable {
    /// Added to the course incline before rounding and clamping. Flat course terrain becomes this incline.
    public let baselinePercent: Double
    public let minimumPercent: Double
    public let maximumPercent: Double
    public let incrementPercent: Double

    /// Defaults match a Peloton Tread.
    public init(
        baselinePercent: Double = 0, minimumPercent: Double = 0, maximumPercent: Double = 12.5,
        incrementPercent: Double = 0.5
    ) {
        precondition(minimumPercent <= maximumPercent, "minimumPercent must not exceed maximumPercent")
        precondition(incrementPercent > 0, "incrementPercent must be positive")
        self.baselinePercent = baselinePercent
        self.minimumPercent = minimumPercent
        self.maximumPercent = maximumPercent
        self.incrementPercent = incrementPercent
    }

    /// Peloton Tread: 0–12.5% in 0.5% steps, no decline. The default.
    public static let pelotonTread = TreadmillSettings()

    /// Peloton Tread+: 0–15% in 0.5% steps, no decline.
    public static let pelotonTreadPlus = TreadmillSettings(maximumPercent: 15)

    /// The incline to tell the runner for a given course incline.
    ///
    /// Adds the baseline, rounds to the increment (half away from zero), then clamps to the treadmill's range.
    /// Rounding happens before clamping so the result can never exceed the treadmill's limits, even when a
    /// limit isn't a multiple of the increment.
    public func treadmillIncline(forCourseIncline courseIncline: Double) -> Double {
        let rounded =
            ((courseIncline + baselinePercent) / incrementPercent).rounded(.toNearestOrAwayFromZero)
            * incrementPercent
        let clamped = min(max(rounded, minimumPercent), maximumPercent)
        // Normalize -0.0 so it never displays as "-0".
        return clamped == 0 ? 0 : clamped
    }
}

/// A stretch of the workout with one treadmill incline.
public struct TreadmillInterval: Equatable, Sendable {
    /// Absolute course position.
    public let startMeters: Double
    /// Absolute course position.
    public let endMeters: Double
    public let inclinePercent: Double

    public init(startMeters: Double, endMeters: Double, inclinePercent: Double) {
        self.startMeters = startMeters
        self.endMeters = endMeters
        self.inclinePercent = inclinePercent
    }
}

/// The treadmill inclines for one segment of a course: what the workout engine follows.
///
/// Intervals are contiguous, cover the segment exactly, and never have equal neighbours. Positions are absolute
/// course meters; the distance into the workout is `position - segment.startMeters`.
public struct TreadmillProfile: Equatable, Sendable {
    public let segment: CourseSegment
    public let settings: TreadmillSettings
    public let intervals: [TreadmillInterval]

    /// - Precondition: `course.contains(segment)`. Segments from the course's own API always satisfy this.
    public init(course: Course, segment: CourseSegment, settings: TreadmillSettings = .pelotonTread) {
        precondition(course.contains(segment), "segment \(segment.id) is outside course \(course.id)")
        self.segment = segment
        self.settings = settings

        var intervals: [TreadmillInterval] = []
        for interval in course.inclineIntervals
        where interval.startMeters < segment.endMeters && interval.endMeters > segment.startMeters {
            let start = max(interval.startMeters, segment.startMeters)
            let end = min(interval.endMeters, segment.endMeters)
            let incline = settings.treadmillIncline(forCourseIncline: interval.inclinePercent)
            if let last = intervals.last, last.inclinePercent == incline {
                intervals[intervals.count - 1] = TreadmillInterval(
                    startMeters: last.startMeters, endMeters: end, inclinePercent: incline)
            } else {
                intervals.append(TreadmillInterval(startMeters: start, endMeters: end, inclinePercent: incline))
            }
        }
        self.intervals = intervals
    }
}
