import CourseKit
import Foundation
import Testing

@testable import WorkoutKit

@Suite("Workout progress")
struct WorkoutProgressTests {
    @Test("Distance is speed × running time")
    func constantSpeed() throws {
        var workout = try TestHills.workout()
        startRun(&workout)

        let snapshot = workout.snapshot(at: at(103))

        #expect(isClose(snapshot.distanceMeters, 100 * sixMph))
        #expect(snapshot.activeElapsed == .seconds(100))
    }

    @Test("Distance sums each stretch at its own speed")
    func speedChanges() throws {
        var workout = try TestHills.workout()
        startRun(&workout)
        workout.setSpeed(.mph(8), at: at(53))
        workout.setSpeed(.mph(5), at: at(83))

        let distance = workout.snapshot(at: at(93)).distanceMeters

        let expected = 50 * sixMph + 30 * Speed.mph(8).metersPerSecond + 10 * Speed.mph(5).metersPerSecond
        #expect(isClose(distance, expected))
    }

    @Test("Distance and active time are frozen while paused")
    func pausedFreezes() throws {
        var workout = try TestHills.workout()
        startRun(&workout)
        workout.pause(at: at(13))
        #expect(isClose(workout.snapshot(at: at(100)).distanceMeters, 10 * sixMph))
        workout.resume(at: at(113))

        let snapshot = workout.snapshot(at: at(123))

        #expect(isClose(snapshot.distanceMeters, 20 * sixMph))
        #expect(snapshot.activeElapsed == .seconds(20))
    }

    @Test("Nothing moves during the countdown, which counts 3, 2, 1")
    func countdownSnapshot() throws {
        var workout = try TestHills.workout()
        workout.startCountdown(at: .zero, wallClock: startDate)

        #expect(workout.snapshot(at: at(0.5)).countdownRemaining == 3)
        #expect(workout.snapshot(at: at(1)).countdownRemaining == 2)
        #expect(workout.snapshot(at: at(2.5)).countdownRemaining == 1)
        let snapshot = workout.snapshot(at: at(2.5))
        #expect(snapshot.state == .countingDown)
        #expect(snapshot.distanceMeters == 0)
        #expect(snapshot.activeElapsed == .zero)
        #expect(workout.snapshot(at: at(3)).state == .running)
        #expect(workout.snapshot(at: at(3)).countdownRemaining == nil)
    }

    @Test("Snapshot reports position, remaining distance, and the next change")
    func snapshotValues() throws {
        var workout = try TestHills.workout()
        startRun(&workout)

        let snapshot = workout.snapshot(at: at(53))

        let covered = 50 * sixMph
        #expect(snapshot.state == .running)
        #expect(isClose(snapshot.distanceMeters, covered))
        #expect(isClose(snapshot.coursePositionMeters, covered))
        #expect(isClose(snapshot.remainingMeters, 2400 - covered))
        #expect(isClose(snapshot.fractionComplete, covered / 2400))
        #expect(snapshot.currentInclinePercent == 1)
        #expect(snapshot.speed == .mph(6))
        let next = try #require(snapshot.nextChange)
        #expect(next.inclinePercent == 3)
        #expect(isClose(next.distanceMeters, 200 - covered))
        #expect(isClose(next.timeRemaining.seconds, (200 - covered) / sixMph))
    }

    @Test("Before the start, the snapshot shows the starting incline and first change")
    func readySnapshot() throws {
        let workout = try TestHills.workout()

        let snapshot = workout.snapshot(at: at(10))

        #expect(snapshot.state == .ready)
        #expect(snapshot.currentInclinePercent == 1)
        #expect(snapshot.nextChange?.inclinePercent == 3)
        #expect(snapshot.distanceMeters == 0)
    }

    @Test("A segment starting mid-course reports course position separately from workout distance")
    func midCourseSegment() throws {
        var workout = try TestHills.workout(segment: (250, 1050))
        let events = startRun(&workout)

        #expect(events.last?.kind == .started(inclinePercent: 3))
        let snapshot = workout.snapshot(at: at(53))
        #expect(isClose(snapshot.distanceMeters, 50 * sixMph))
        #expect(isClose(snapshot.coursePositionMeters, 250 + 50 * sixMph))
        #expect(isClose(snapshot.remainingMeters, 800 - 50 * sixMph))
        #expect(snapshot.nextChange?.inclinePercent == 6.5)
        #expect(isClose(snapshot.nextChange?.distanceMeters ?? 0, 150 - 50 * sixMph))
    }

    @Test("Time going backwards is ignored")
    func timeGoingBackwards() throws {
        var workout = try TestHills.workout()
        startRun(&workout)
        workout.advance(to: at(50))

        #expect(workout.advance(to: at(40)).isEmpty)
        #expect(isClose(workout.snapshot(at: at(40)).distanceMeters, 47 * sixMph))
    }
}

@Suite("Speed")
struct SpeedTests {
    @Test(
        "Speeds round to 0.1 mph and stay within 0.5–12.5 mph",
        arguments: [(6.04, 6.0), (6.06, 6.1), (0.0, 0.5), (-3.0, 0.5), (20.0, 12.5), (12.5, 12.5), (0.5, 0.5)])
    func rounding(input: Double, expected: Double) {
        #expect(isClose(Speed.mph(input).mph, expected))
    }

    @Test("Stepping moves in 0.1 mph steps within range")
    func stepping() {
        #expect(isClose(Speed.mph(6).stepped(by: 3).mph, 6.3))
        #expect(isClose(Speed.mph(6).stepped(by: -1).mph, 5.9))
        #expect(Speed.mph(12.4).stepped(by: 5) == .mph(12.5))
        #expect(Speed.mph(0.6).stepped(by: -5) == .mph(0.5))
    }

    @Test("1 mph is 0.44704 m/s")
    func conversion() {
        #expect(isClose(Speed.mph(10).metersPerSecond, 4.4704))
    }

    @Test("Speed encodes as mph and re-applies limits when decoded")
    func codable() throws {
        #expect(String(decoding: try JSONEncoder().encode(Speed.mph(6.5)), as: UTF8.self) == "6.5")
        #expect(try JSONDecoder().decode(Speed.self, from: Data("40".utf8)) == .mph(12.5))
    }
}
