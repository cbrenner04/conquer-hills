import CourseKit
import Foundation
import Testing

@testable import WorkoutKit

@Suite("Workout record and lifecycle")
struct WorkoutRecordTests {
    @Test("The record captures speed changes, pauses, incline changes, and times")
    func scriptedRun() throws {
        var workout = try TestHills.workout()
        workout.setSpeed(.mph(6.5), at: .zero)  // before the start: replaces the starting speed
        workout.setSpeed(.mph(6), at: .zero)
        startRun(&workout)
        workout.setSpeed(.mph(7), at: at(23))
        workout.pause(at: at(43))
        workout.resume(at: at(73))
        workout.advance(to: at(150))
        workout.end(at: at(150))

        let record = workout.record
        let seven = Speed.mph(7).metersPerSecond
        let distanceAtPause = 20 * sixMph + 20 * seven
        #expect(record.course == CourseIdentity(id: "test-hills", name: "Test Hills", edition: "Synthetic"))
        #expect(record.segment.kind == .fullCourse)
        #expect(record.settings == .pelotonTread)
        #expect(record.startingSpeed == .mph(6))
        #expect(record.startingInclinePercent == 1)
        #expect(record.speedChanges.count == 1)
        #expect(record.speedChanges.first?.speed == .mph(7))
        #expect(isClose(record.speedChanges.first?.distanceMeters ?? 0, 20 * sixMph))
        #expect(record.speedChanges.first?.activeElapsed == .seconds(20))
        #expect(record.pauses.count == 1)
        #expect(isClose(record.pauses.first?.distanceMeters ?? 0, distanceAtPause))
        #expect(record.pauses.first?.duration == .seconds(30))
        #expect(record.inclineChanges.map(\.toPercent) == [3])
        #expect(record.inclineChanges.first?.distanceMeters == 200)
        #expect(record.outcome == .endedEarly)
        #expect(record.startedAt == startDate.addingTimeInterval(3))
        #expect(record.endedAt == startDate.addingTimeInterval(150))
        #expect(record.activeDuration == .seconds(117))
        #expect(isClose(record.distanceMeters, 20 * sixMph + 97 * seven))
        #expect(record.maximumInclinePercent == 3)
        #expect(record.averageSpeed == .mph(record.distanceMeters / 117 / Speed.metersPerSecondPerMph))
    }

    @Test("Ending while paused closes the pause and ends early")
    func endWhilePaused() throws {
        var workout = try TestHills.workout()
        startRun(&workout)
        workout.pause(at: at(13))

        workout.end(at: at(33))

        #expect(workout.state == .endedEarly)
        #expect(workout.record.outcome == .endedEarly)
        #expect(workout.record.pauses.first?.duration == .seconds(20))
        #expect(workout.record.activeDuration == .seconds(10))
        #expect(workout.record.endedAt == startDate.addingTimeInterval(33))
    }

    @Test("A finished run's end time comes from the exact finish moment")
    func finishedEndDate() throws {
        var workout = try TestHills.workout()
        startRun(&workout)
        workout.advance(to: at(5000))

        let finish = 3 + 2400 / sixMph
        let endedAt = try #require(workout.record.endedAt)
        #expect(isClose(endedAt.timeIntervalSince(startDate), finish))
    }

    @Test("Calls that don't fit the current state are ignored")
    func invalidCalls() throws {
        var workout = try TestHills.workout()
        #expect(workout.pause(at: .zero).isEmpty)
        #expect(workout.resume(at: .zero).isEmpty)
        #expect(workout.end(at: .zero).isEmpty)
        #expect(workout.cancelCountdown(at: .zero).isEmpty)
        #expect(workout.state == .ready)

        startRun(&workout)
        #expect(workout.startCountdown(at: at(4), wallClock: startDate).isEmpty)
        #expect(workout.resume(at: at(4)).isEmpty)
        #expect(workout.state == .running)

        workout.end(at: at(5))
        #expect(workout.setSpeed(.mph(9), at: at(6)).isEmpty)
        #expect(workout.speed == .mph(6))
        #expect(workout.pause(at: at(7)).isEmpty)
        #expect(workout.state == .endedEarly)
    }

    @Test("A workout saved and restored mid-run carries on identically")
    func codableRoundTrip() throws {
        var workout = try TestHills.workout()
        startRun(&workout)
        workout.advance(to: at(100))
        workout.setSpeed(.mph(7.5), at: at(100))
        workout.pause(at: at(120))

        var restored = try JSONDecoder().decode(Workout.self, from: JSONEncoder().encode(workout))
        #expect(restored == workout)

        let original = workout.resume(at: at(130)) + workout.advance(to: at(600))
        let replayed = restored.resume(at: at(130)) + restored.advance(to: at(600))
        #expect(original == replayed)
        #expect(restored == workout)
    }

    @Test("The run record survives encoding")
    func recordCodable() throws {
        var workout = try TestHills.workout()
        startRun(&workout)
        workout.advance(to: at(5000))

        let decoded = try JSONDecoder().decode(WorkoutRecord.self, from: JSONEncoder().encode(workout.record))

        #expect(decoded == workout.record)
    }
}
