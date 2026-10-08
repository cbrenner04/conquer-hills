import CourseKit
import Foundation
import Observation
import UIKit
import WorkoutKit

/// Drives one run: owns the `Workout`, ticks it from `ContinuousClock`, speaks prompts, and keeps the screen awake.
@Observable
final class RunModel: Identifiable {
    struct LastChange: Equatable {
        let fromPercent: Double
        let toPercent: Double
        let at: Date

        var isUp: Bool { toPercent > fromPercent }
    }

    let id = UUID()
    let courseName: String
    private(set) var workout: Workout
    private(set) var snapshot: WorkoutSnapshot
    /// True between a warning and the change it warns about.
    private(set) var warningActive = false
    private(set) var lastChange: LastChange?
    /// Increments on every incline change; drives the screen flash and haptic.
    private(set) var changeCount = 0

    private let clockOrigin = ContinuousClock.now
    private var tickTask: Task<Void, Never>?
    private let announcer = SpeechAnnouncer()

    init(course: Course, segment: CourseSegment, settings: TreadmillSettings, startingSpeed: Speed) {
        courseName = course.name
        let workout = Workout(course: course, segment: segment, settings: settings, startingSpeed: startingSpeed)
        self.workout = workout
        snapshot = workout.snapshot(at: .zero)
    }

    var segmentName: String { workout.profile.segment.name ?? "Custom segment" }
    var isOver: Bool { workout.state.isOver }

    /// Time on the app's clock. `ContinuousClock` keeps counting while the phone sleeps.
    private var now: Duration { clockOrigin.duration(to: .now) }

    // MARK: Commands

    func start() {
        UIApplication.shared.isIdleTimerDisabled = true
        apply(workout.startCountdown(at: now, wallClock: Date()))
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                self?.tick()
            }
        }
    }

    func changeSpeed(bySteps steps: Int) {
        apply(workout.setSpeed(workout.speed.stepped(by: steps), at: now))
    }

    func pause() { apply(workout.pause(at: now)) }

    func resume() { apply(workout.resume(at: now)) }

    func end() { apply(workout.end(at: now)) }

    /// Stops ticking and speech and lets the screen sleep again. Called when the run screen goes away.
    func stop() {
        tickTask?.cancel()
        tickTask = nil
        announcer.stop()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: Processing

    private func tick() {
        apply(workout.advance(to: now))
    }

    private func apply(_ events: [WorkoutEvent]) {
        snapshot = workout.snapshot(at: now)
        for event in events {
            switch event.kind {
            case .upcomingChange:
                warningActive = true
            case .inclineChange(let from, let to):
                warningActive = false
                lastChange = LastChange(fromPercent: from, toPercent: to, at: Date())
                changeCount += 1
            case .finished:
                warningActive = false
            case .countdown, .started, .resumed:
                break
            }
        }
        announcer.speak(
            AnnouncementPolicy.announcements(for: events, currentInclinePercent: snapshot.currentInclinePercent))
        if workout.state.isOver {
            tickTask?.cancel()
            tickTask = nil
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
}
