import CourseKit
import Foundation
import Testing

@testable import WorkoutKit

@Suite("Run preview")
struct RunPreviewTests {
    /// Runs the engine over a segment at a steady speed and counts the incline changes it announces.
    private func announcedChanges(course: Course, segment: CourseSegment, settings: TreadmillSettings, mph: Double)
        -> Int
    {
        var workout = Workout(course: course, segment: segment, settings: settings, startingSpeed: .mph(mph))
        var events = workout.startCountdown(at: .zero, wallClock: startDate)
        events += workout.advance(to: .seconds(100_000))
        return events.filter(\.isChange).count
    }

    @Test(
        "The preview's change count matches what the engine announces",
        arguments: [
            (0.0, 2400.0, 6.0, 1.0), (0.0, 2030.0, 6.0, 1.0), (250.0, 1050.0, 9.0, 0.0), (0.0, 2400.0, 12.5, 2.0),
        ])
    func matchesEngine(start: Double, end: Double, mph: Double, baseline: Double) throws {
        let course = try TestHills.course()
        let segment = try #require(course.customSegment(startMeters: start, endMeters: end))
        let settings = TreadmillSettings(baselinePercent: baseline)

        let preview = RunPreview(
            profile: TreadmillProfile(course: course, segment: segment, settings: settings), speed: .mph(mph))

        #expect(
            preview.inclineChangeCount
                == announcedChanges(course: course, segment: segment, settings: settings, mph: mph))
    }

    @Test("Bundled marathons: preview matches the engine for full courses and curated segments")
    func bundledCourses() throws {
        let directory = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "App/Resources/Courses")
        let courses = CourseLoader.loadAll(in: directory).courses.filter { !$0.isDevelopmentOnly }
        try #require(!courses.isEmpty)
        for course in courses {
            for segment in course.predefinedSegments {
                let settings = TreadmillSettings(baselinePercent: 1)
                let preview = RunPreview(
                    profile: TreadmillProfile(course: course, segment: segment, settings: settings), speed: .mph(6))
                #expect(
                    preview.inclineChangeCount
                        == announcedChanges(course: course, segment: segment, settings: settings, mph: 6),
                    "\(course.id) \(segment.id)")
            }
        }
    }

    @Test("Estimated time is distance at the given speed, and the starting incline is the first interval's")
    func durationAndStart() throws {
        let course = try TestHills.course()

        let preview = RunPreview(
            profile: TreadmillProfile(course: course, segment: course.fullCourseSegment), speed: .mph(6))

        #expect(isClose(preview.estimatedDuration.seconds, 2400 / sixMph))
        #expect(preview.startingInclinePercent == 1)
    }
}
