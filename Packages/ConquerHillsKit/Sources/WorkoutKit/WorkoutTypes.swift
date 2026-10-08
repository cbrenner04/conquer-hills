import CourseKit
import Foundation

/// The tunable timings of a workout, grouped so treadmill testing can adjust them in one place.
public struct WorkoutConfiguration: Equatable, Sendable, Codable {
    /// Length of the 3-2-1 countdown before the run starts.
    public var countdownSeconds: Int
    /// How long before an incline change, at the current speed, the runner is warned.
    public var warningLead: Duration
    /// A warning that would come with less time than this left is skipped; only the change is announced.
    public var minimumWarningLead: Duration
    /// A final change the runner would hold for less than this before the finish is skipped.
    public var minimumFinalHold: Duration
    /// Events returned more than this long after they were due are marked late.
    public var lateThreshold: Duration

    public init(
        countdownSeconds: Int = 3, warningLead: Duration = .seconds(10), minimumWarningLead: Duration = .seconds(3),
        minimumFinalHold: Duration = .seconds(15), lateThreshold: Duration = .seconds(3)
    ) {
        self.countdownSeconds = countdownSeconds
        self.warningLead = warningLead
        self.minimumWarningLead = minimumWarningLead
        self.minimumFinalHold = minimumFinalHold
        self.lateThreshold = lateThreshold
    }

    public static let standard = WorkoutConfiguration()
}

/// Identifies the course a workout is on, for the run record.
public struct CourseIdentity: Equatable, Sendable, Codable {
    public let id: String
    public let name: String
    public let edition: String

    public init(id: String, name: String, edition: String) {
        self.id = id
        self.name = name
        self.edition = edition
    }

    public init(_ course: Course) {
        self.init(id: course.id, name: course.name, edition: course.edition)
    }
}

public enum WorkoutState: String, Equatable, Sendable, Codable {
    case ready
    case countingDown
    case running
    case paused
    /// The segment end was reached.
    case finished
    /// The runner ended the run before the segment end.
    case endedEarly

    public var isOver: Bool { self == .finished || self == .endedEarly }
}

/// Something the runner should be told, returned by the engine in the order it happened.
public struct WorkoutEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Countdown before the start: 3, 2, 1.
        case countdown(Int)
        /// The run has started; set the treadmill to this incline.
        case started(inclinePercent: Double)
        /// An incline change is coming up.
        case upcomingChange(fromPercent: Double, toPercent: Double, secondsRemaining: Double)
        /// Change the incline now.
        case inclineChange(fromPercent: Double, toPercent: Double)
        /// The run has resumed; the treadmill should be at this incline.
        case resumed(inclinePercent: Double)
        /// The segment end was reached.
        case finished
    }

    public let kind: Kind
    /// When the event was due, on the app's clock.
    public let dueAt: Duration
    /// True when the event is returned well after it was due, e.g. because the app wasn't checking.
    public let isLate: Bool

    public init(kind: Kind, dueAt: Duration, isLate: Bool) {
        self.kind = kind
        self.dueAt = dueAt
        self.isLate = isLate
    }
}

/// A read-only summary of a workout at a moment in time, for the screen.
public struct WorkoutSnapshot: Equatable, Sendable {
    public struct NextChange: Equatable, Sendable {
        public let inclinePercent: Double
        /// Distance from the runner to the change.
        public let distanceMeters: Double
        /// Time to the change at the current speed.
        public let timeRemaining: Duration
    }

    public let state: WorkoutState
    /// Seconds left in the countdown (3, 2, 1) while counting down; otherwise nil.
    public let countdownRemaining: Int?
    /// Running time, excluding the countdown and pauses.
    public let activeElapsed: Duration
    /// Distance covered in this workout.
    public let distanceMeters: Double
    /// Absolute position on the course.
    public let coursePositionMeters: Double
    public let remainingMeters: Double
    /// The incline the runner has been told to use.
    public let currentInclinePercent: Double
    /// The next change that will be announced, or nil if none remain.
    public let nextChange: NextChange?
    public let speed: Speed
    /// Distance covered as a fraction of the segment, 0 to 1.
    public let fractionComplete: Double
}

/// What happened in a workout: shown in the completion summary and saved to history (spec 08).
public struct WorkoutRecord: Equatable, Sendable, Codable {
    public enum Outcome: String, Equatable, Sendable, Codable {
        case finished
        case endedEarly
    }

    public struct SpeedChange: Equatable, Sendable, Codable {
        public let distanceMeters: Double
        public let activeElapsed: Duration
        public let speed: Speed
    }

    public struct Pause: Equatable, Sendable, Codable {
        public let distanceMeters: Double
        public let duration: Duration
    }

    public struct InclineChange: Equatable, Sendable, Codable {
        public let distanceMeters: Double
        public let fromPercent: Double
        public let toPercent: Double
    }

    public let course: CourseIdentity
    public let segment: CourseSegment
    public let settings: TreadmillSettings
    /// Wall-clock time the run started (after the countdown); nil until it starts.
    public internal(set) var startedAt: Date?
    /// Wall-clock time the run finished or was ended; nil while in progress.
    public internal(set) var endedAt: Date?
    public internal(set) var outcome: Outcome?
    public internal(set) var activeDuration: Duration
    public internal(set) var distanceMeters: Double
    public internal(set) var startingSpeed: Speed
    public let startingInclinePercent: Double
    public internal(set) var speedChanges: [SpeedChange]
    public internal(set) var pauses: [Pause]
    public internal(set) var inclineChanges: [InclineChange]

    /// Mean speed over active running time, or nil before any running.
    public var averageSpeed: Speed? {
        let seconds = activeDuration.seconds
        guard seconds > 0 else { return nil }
        return .mph(distanceMeters / seconds / Speed.metersPerSecondPerMph)
    }

    /// The highest incline the runner was told to use.
    public var maximumInclinePercent: Double {
        inclineChanges.map(\.toPercent).reduce(startingInclinePercent, max)
    }
}

extension Duration {
    /// This duration in seconds, as a `Double`.
    var seconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) * 1e-18
    }
}
