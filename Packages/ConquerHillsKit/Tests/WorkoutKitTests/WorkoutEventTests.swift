import CourseKit
import Foundation
import Testing

@testable import WorkoutKit

@Suite("Workout events")
struct WorkoutEventTests {
    @Test("The countdown counts 3, 2, 1, then starts at the first incline")
    func countdownEvents() throws {
        var workout = try TestHills.workout()

        let first = workout.startCountdown(at: .zero, wallClock: startDate)
        let rest = workout.advance(to: at(3))

        #expect(first.map(\.kind) == [.countdown(3)])
        #expect(rest.map(\.kind) == [.countdown(2), .countdown(1), .started(inclinePercent: 1)])
        #expect(rest.map(\.due) == [1, 2, 3])
        #expect(workout.state == .running)
    }

    @Test("Cancelling the countdown returns to ready, and it can be started again")
    func cancelCountdown() throws {
        var workout = try TestHills.workout()
        workout.startCountdown(at: .zero, wallClock: startDate)

        workout.cancelCountdown(at: at(1.5))

        #expect(workout.state == .ready)
        #expect(workout.advance(to: at(10)).isEmpty)
        let restarted = workout.startCountdown(at: at(10), wallClock: startDate) + workout.advance(to: at(13))
        #expect(restarted.last?.kind == .started(inclinePercent: 1))
        #expect(restarted.last?.due == 13)
    }

    @Test("A zero-length countdown starts immediately")
    func noCountdown() throws {
        var workout = try TestHills.workout(configuration: WorkoutConfiguration(countdownSeconds: 0))

        let events = workout.startCountdown(at: at(5), wallClock: startDate)

        #expect(events.map(\.kind) == [.started(inclinePercent: 1)])
        #expect(workout.state == .running)
    }

    /// Runs the whole Test Hills course at 6 mph, checking every half second like the app would.
    private func fullRunEvents() throws -> [WorkoutEvent] {
        var workout = try TestHills.workout()
        var events = startRun(&workout)
        var time = 3.0
        while workout.state == .running {
            time += 0.5
            events += workout.advance(to: at(time))
        }
        return events
    }

    @Test("Every change is warned 10 s ahead and announced once, in order, then the run finishes")
    func fullCourse() throws {
        let events = try fullRunEvents().filter { $0.isWarning || $0.isChange || $0.kind == .finished }

        var expected: [(kind: WorkoutEvent.Kind, due: Double)] = []
        var from = 1.0
        for change in TestHills.changes {
            let reach = 3 + change.meters / sixMph
            expected.append(
                (.upcomingChange(fromPercent: from, toPercent: change.toPercent, secondsRemaining: 10), reach - 10))
            expected.append((.inclineChange(fromPercent: from, toPercent: change.toPercent), reach))
            from = change.toPercent
        }
        expected.append((.finished, 3 + TestHills.length / sixMph))

        try #require(events.count == expected.count)
        for (event, expectation) in zip(events, expected) {
            #expect(isClose(event.due, expectation.due, tolerance: 1e-6))
            switch (event.kind, expectation.kind) {
            case (.upcomingChange(let from, let to, let seconds), .upcomingChange(let eFrom, let eTo, let eSeconds)):
                #expect(from == eFrom && to == eTo && isClose(seconds, eSeconds))
            default:
                #expect(event.kind == expectation.kind)
            }
            #expect(!event.isLate)
        }
    }

    @Test("Catching up after a long gap returns the same events in order, with old ones marked late")
    func catchUp() throws {
        let ticked = try fullRunEvents()
        var workout = try TestHills.workout()
        var caughtUp = startRun(&workout)
        caughtUp += workout.advance(to: at(60))
        caughtUp += workout.advance(to: at(180))  // a 2-minute gap
        caughtUp += workout.advance(to: at(2000))

        #expect(caughtUp.map(\.kind).count == ticked.count)
        for (a, b) in zip(caughtUp, ticked) {
            #expect(isClose(a.due, b.due))
        }
        let gap = caughtUp.filter { $0.due > 60 && $0.due <= 180 }
        #expect(!gap.isEmpty)
        #expect(gap.allSatisfy { $0.isLate == (180 - $0.due > 3) })
    }

    @Test("A speed change before the warning moves the warning")
    func warningFollowsSpeed() throws {
        var workout = try TestHills.workout()
        startRun(&workout)
        workout.setSpeed(.mph(8), at: at(30))

        let events = workout.advance(to: at(70))

        let eight = Speed.mph(8).metersPerSecond
        let reach = 30 + (200 - 27 * sixMph) / eight
        let warning = try #require(events.first { $0.isWarning })
        #expect(isClose(warning.due, reach - 10))
        let change = try #require(events.first { $0.isChange })
        #expect(isClose(change.due, reach))
    }

    @Test("Slowing down after a warning doesn't repeat it")
    func noRepeatWarning() throws {
        var workout = try TestHills.workout()
        startRun(&workout)
        let beforeChange = workout.advance(to: at(70))
        #expect(beforeChange.filter(\.isWarning).count == 1)

        var after = workout.setSpeed(.mph(3), at: at(70))
        after += workout.advance(to: at(120))

        #expect(after.filter(\.isWarning).isEmpty)
        #expect(after.filter(\.isChange).count == 1)
    }

    @Test("Speeding up into a warning window warns at once if at least 3 s remain")
    func speedUpIntoWindow() throws {
        var workout = try TestHills.workout(mph: 2)
        startRun(&workout)
        // At 2 mph the warning window starts 8.9 m before the 200 m change. Speed up at 3 + 179 s, about 40 m
        // short: at 12 mph that's 7.5 s away, inside the window but more than 3 s, so the warning comes at once.
        let events = workout.setSpeed(.mph(12), at: at(182))

        let warning = try #require(events.first)
        guard case .upcomingChange(_, _, let seconds) = warning.kind else {
            Issue.record("Expected a warning, got \(warning.kind)")
            return
        }
        #expect(warning.due == 182)
        #expect(isClose(seconds, (200 - 179 * Speed.mph(2).metersPerSecond) / Speed.mph(12).metersPerSecond))
    }

    @Test("A change under 3 s away when the run starts gets no warning")
    func warningSkippedWhenTooClose() throws {
        var workout = try TestHills.workout(segment: (195, 2400))

        var events = startRun(&workout)
        events += workout.advance(to: at(10))

        #expect(!events.contains { $0.isWarning })
        let change = try #require(events.first { $0.isChange })
        #expect(isClose(change.due, 3 + 5 / sixMph))
    }

    @Test("A change 3–10 s away when the run starts is warned at the start")
    func shortWarningAtStart() throws {
        var workout = try TestHills.workout(segment: (180, 2400))

        let events = startRun(&workout)

        let warning = try #require(events.last)
        guard case .upcomingChange(1, 3, let seconds) = warning.kind else {
            Issue.record("Expected a warning, got \(warning.kind)")
            return
        }
        #expect(warning.due == 3)
        #expect(isClose(seconds, 20 / sixMph))
    }

    @Test("A change reached while paused is announced after resuming, which repeats the current incline")
    func pauseBeforeChange() throws {
        var workout = try TestHills.workout()
        startRun(&workout)
        workout.advance(to: at(77))  // about half a second before the 200 m change
        workout.pause(at: at(77))

        #expect(workout.advance(to: at(137)).isEmpty)
        let events = workout.resume(at: at(137)) + workout.advance(to: at(140))

        #expect(events.first?.kind == .resumed(inclinePercent: 1))
        let change = try #require(events.first { $0.isChange })
        #expect(change.kind == .inclineChange(fromPercent: 1, toPercent: 3))
        #expect(isClose(change.due, 137 + (200 - 74 * sixMph) / sixMph))
        #expect(!events.contains { $0.isWarning })
    }

    @Test("A final change held under 15 s before the finish is skipped entirely")
    func shortFinalChangeSkipped() throws {
        var workout = try TestHills.workout(segment: (0, 2030))  // 30 m after the 2000 m change ≈ 11 s
        var events = startRun(&workout)
        events += workout.advance(to: at(2000))

        #expect(!events.contains { $0.kind == .inclineChange(fromPercent: 0, toPercent: 2.5) })
        #expect(!events.contains { $0.kind.isWarning(to: 2.5) })
        #expect(events.last?.kind == .finished)
        #expect(workout.record.inclineChanges.count == 8)
        #expect(workout.snapshot(at: at(2000)).currentInclinePercent == 0)
    }

    @Test("A final change held 15 s or more is announced")
    func longerFinalChangeKept() throws {
        var workout = try TestHills.workout(segment: (0, 2050))  // 50 m ≈ 18.6 s
        var events = startRun(&workout)
        events += workout.advance(to: at(2000))

        #expect(events.contains { $0.kind == .inclineChange(fromPercent: 0, toPercent: 2.5) })
    }

    @Test("The snapshot hides a final change that will be skipped")
    func snapshotHidesSkippedChange() throws {
        var workout = try TestHills.workout(segment: (0, 2030))
        startRun(&workout)

        let snapshot = workout.snapshot(at: at(3 + 1900 / sixMph))

        #expect(snapshot.nextChange == nil)
    }

    @Test("Finishing between checks happens at the exact moment the end is reached")
    func finishBetweenChecks() throws {
        var workout = try TestHills.workout()
        startRun(&workout)

        let events = workout.advance(to: at(1000))

        let finishTime = 3 + 2400 / sixMph
        let finish = try #require(events.last)
        #expect(finish.kind == .finished)
        #expect(isClose(finish.due, finishTime))
        #expect(finish.isLate)
        #expect(workout.state == .finished)
        #expect(isClose(workout.record.activeDuration.seconds, finishTime - 3))
        #expect(workout.record.distanceMeters == 2400)
        #expect(workout.end(at: at(1100)).isEmpty)
        #expect(workout.record.outcome == .finished)
        #expect(workout.advance(to: at(2000)).isEmpty)
    }
}

extension WorkoutEvent.Kind {
    func isWarning(to percent: Double) -> Bool {
        if case .upcomingChange(_, percent, _) = self { return true }
        return false
    }
}
