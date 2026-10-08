import CourseKit
import Foundation
import Testing

@testable import WorkoutKit

/// The bundled Test Hills course. With Peloton Tread defaults its profile is: start at 1%, then changes at
/// 200 m → 3, 400 → 6.5, 600 → 2, 700 → 0, 1100 → 0.5, 1300 → 12.5, 1500 → 4.5, 1700 → 0, 2000 → 2.5, finish 2400.
enum TestHills {
    static let changes: [(meters: Double, toPercent: Double)] = [
        (200, 3), (400, 6.5), (600, 2), (700, 0), (1100, 0.5), (1300, 12.5), (1500, 4.5), (1700, 0), (2000, 2.5),
    ]
    static let length = 2400.0

    static func course() throws -> Course {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()  // WorkoutKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // ConquerHillsKit
            .deletingLastPathComponent()  // Packages
            .deletingLastPathComponent()  // repository root
            .appending(path: "App/Resources/Courses/test-hills.course.json")
        return try CourseLoader.load(Data(contentsOf: url), fileName: "test-hills.course.json").get()
    }

    /// A workout on the full course (or a custom segment), at 6 mph by default.
    static func workout(
        segment: (start: Double, end: Double)? = nil, mph: Double = 6,
        configuration: WorkoutConfiguration = .standard
    ) throws -> Workout {
        let course = try course()
        let chosen = try segment.map { try #require(course.customSegment(startMeters: $0.start, endMeters: $0.end)) }
        return Workout(
            course: course, segment: chosen ?? course.fullCourseSegment, startingSpeed: .mph(mph),
            configuration: configuration)
    }
}

let sixMph = Speed.mph(6).metersPerSecond
let startDate = Date(timeIntervalSince1970: 1_800_000_000)

/// Shorthand for a time on the app's clock.
func at(_ seconds: Double) -> Duration { .seconds(seconds) }

func isClose(_ a: Double, _ b: Double, tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }

extension WorkoutEvent {
    var due: Double { dueAt.seconds }

    var isWarning: Bool {
        if case .upcomingChange = kind { return true }
        return false
    }

    var isChange: Bool {
        if case .inclineChange = kind { return true }
        return false
    }
}

/// Starts a workout's countdown at time 0 and returns the events up to and including the start at 3 s.
@discardableResult
func startRun(_ workout: inout Workout) -> [WorkoutEvent] {
    workout.startCountdown(at: .zero, wallClock: startDate) + workout.advance(to: at(3))
}
