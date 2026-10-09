import CourseKit

/// What a run will be like before it starts: how many incline changes will be announced, how long it takes at a
/// steady speed, and the incline to set at the start.
public struct RunPreview: Equatable, Sendable {
    public let inclineChangeCount: Int
    public let estimatedDuration: Duration
    public let startingInclinePercent: Double

    /// Assumes the whole run at `speed`, using the same rules the engine applies (a final change held too briefly
    /// before the finish isn't announced).
    public init(profile: TreadmillProfile, speed: Speed, configuration: WorkoutConfiguration = .standard) {
        let intervals = profile.intervals
        var changes = max(0, intervals.count - 1)
        if let last = intervals.last, intervals.count > 1 {
            let holdSeconds = (last.endMeters - last.startMeters) / speed.metersPerSecond
            if holdSeconds < configuration.minimumFinalHold.seconds {
                changes -= 1
            }
        }
        inclineChangeCount = changes
        estimatedDuration = .seconds(profile.segment.distanceMeters / speed.metersPerSecond)
        startingInclinePercent = intervals.first?.inclinePercent ?? 0
    }
}
