import CourseKit
import Foundation

/// The state of one treadmill run along a segment of a course.
///
/// `Workout` never reads a clock. Every call is given the current time on the app's clock (a `Duration` from any
/// fixed starting point, read from `ContinuousClock`), first catches up to that time, then applies the command.
/// Calls return the events due since the previous call, in order, each with the time it was due.
///
/// Distance is speed × running time, summed over each stretch at one speed; paused time adds nothing. Each
/// incline change is announced at most once with a warning and exactly once when reached. Calls that don't make
/// sense in the current state (pausing when not running, and so on) are ignored.
public struct Workout: Equatable, Sendable, Codable {
    public let profile: TreadmillProfile
    public let configuration: WorkoutConfiguration
    public private(set) var state: WorkoutState = .ready
    public private(set) var speed: Speed
    public private(set) var record: WorkoutRecord

    /// Seconds on the app's clock up to which the workout has been processed.
    private var clock: Double = 0
    private var countdownStart: Double?
    /// The next countdown tick to emit, counted from 1 second after the countdown starts.
    private var nextCountdownTick = 1
    private var runStart: Double?
    private var runStartDate: Date?
    /// Meters covered in this workout.
    private var distance: Double = 0
    private var activeSeconds: Double = 0
    /// The incline the runner has been told to use.
    private var currentIncline: Double
    /// Index into `transitions` of the next change not yet reached.
    private var nextTransition = 0
    /// Index of the transition whose warning has been given or deliberately skipped.
    private var warnedTransition: Int?
    private var pauseStartTime: Double?
    private var pauseStartDistance: Double?

    public init(
        profile: TreadmillProfile, course: CourseIdentity, startingSpeed: Speed,
        configuration: WorkoutConfiguration = .standard
    ) {
        self.profile = profile
        self.configuration = configuration
        self.speed = startingSpeed
        let startingIncline = profile.intervals.first?.inclinePercent ?? 0
        self.currentIncline = startingIncline
        self.record = WorkoutRecord(
            course: course, segment: profile.segment, settings: profile.settings, startedAt: nil, endedAt: nil,
            outcome: nil, activeDuration: .zero, distanceMeters: 0, startingSpeed: startingSpeed,
            startingInclinePercent: startingIncline, speedChanges: [], pauses: [], inclineChanges: [])
    }

    public init(
        course: Course, segment: CourseSegment, settings: TreadmillSettings = .pelotonTread, startingSpeed: Speed,
        configuration: WorkoutConfiguration = .standard
    ) {
        self.init(
            profile: TreadmillProfile(course: course, segment: segment, settings: settings),
            course: CourseIdentity(course), startingSpeed: startingSpeed, configuration: configuration)
    }

    // MARK: - Commands

    /// Starts the 3-2-1 countdown. `wallClock` is the current date, used to timestamp the run record.
    @discardableResult
    public mutating func startCountdown(at time: Duration, wallClock: Date) -> [WorkoutEvent] {
        var events = process(until: time.seconds)
        guard state == .ready else { return events }
        state = .countingDown
        countdownStart = clock
        nextCountdownTick = 1
        runStartDate = wallClock.addingTimeInterval(Double(configuration.countdownSeconds))
        if configuration.countdownSeconds > 0 {
            events.append(event(.countdown(configuration.countdownSeconds), due: clock, now: clock))
        }
        events += process(until: clock)
        return events
    }

    /// Abandons the countdown and returns to ready.
    @discardableResult
    public mutating func cancelCountdown(at time: Duration) -> [WorkoutEvent] {
        let events = process(until: time.seconds)
        guard state == .countingDown else { return events }
        state = .ready
        countdownStart = nil
        runStartDate = nil
        return events
    }

    /// Catches up to `time`, returning the events due since the last call.
    @discardableResult
    public mutating func advance(to time: Duration) -> [WorkoutEvent] {
        process(until: time.seconds)
    }

    /// Records a new treadmill speed, effective at `time`. Before the run starts it replaces the starting speed.
    @discardableResult
    public mutating func setSpeed(_ newSpeed: Speed, at time: Duration) -> [WorkoutEvent] {
        var events = process(until: time.seconds)
        guard !state.isOver, newSpeed != speed else { return events }
        speed = newSpeed
        switch state {
        case .ready, .countingDown:
            record.startingSpeed = newSpeed
        case .running, .paused:
            record.speedChanges.append(
                .init(distanceMeters: distance, activeElapsed: .seconds(activeSeconds), speed: newSpeed))
        case .finished, .endedEarly:
            break
        }
        // A faster speed can bring the next warning due now.
        events += process(until: clock)
        return events
    }

    @discardableResult
    public mutating func pause(at time: Duration) -> [WorkoutEvent] {
        let events = process(until: time.seconds)
        guard state == .running else { return events }
        state = .paused
        pauseStartTime = clock
        pauseStartDistance = distance
        return events
    }

    /// Resumes a paused run, announcing the current incline so the runner can check the treadmill.
    @discardableResult
    public mutating func resume(at time: Duration) -> [WorkoutEvent] {
        var events = process(until: time.seconds)
        guard state == .paused else { return events }
        closePause()
        state = .running
        events.append(event(.resumed(inclinePercent: currentIncline), due: clock, now: clock))
        events += process(until: clock)
        return events
    }

    /// Ends the run before the segment end. Has no effect if the run already finished by `time`.
    @discardableResult
    public mutating func end(at time: Duration) -> [WorkoutEvent] {
        let events = process(until: time.seconds)
        guard state == .running || state == .paused else { return events }
        if state == .paused {
            closePause()
        }
        state = .endedEarly
        record.outcome = .endedEarly
        record.endedAt = wallClockDate(at: clock)
        syncRecord()
        return events
    }

    // MARK: - Queries

    /// A summary of the workout at `time`, without changing it.
    public func snapshot(at time: Duration) -> WorkoutSnapshot {
        var copy = self
        copy.process(until: time.seconds)
        return copy.currentSnapshot()
    }

    // MARK: - Processing

    private struct Transition {
        /// Meters into the workout.
        let distance: Double
        let toPercent: Double
    }

    private var transitions: [Transition] {
        profile.intervals.dropFirst().map {
            Transition(distance: $0.startMeters - profile.segment.startMeters, toPercent: $0.inclinePercent)
        }
    }

    private var segmentLength: Double { profile.segment.distanceMeters }

    /// Whether `index` is the final change and would be held too briefly before the finish to be worth announcing.
    private func isSkippedFinalChange(_ index: Int, transitions: [Transition]) -> Bool {
        guard index == transitions.count - 1 else { return false }
        let holdSeconds = (segmentLength - transitions[index].distance) / speed.metersPerSecond
        return holdSeconds < configuration.minimumFinalHold.seconds
    }

    private func event(_ kind: WorkoutEvent.Kind, due: Double, now: Double) -> WorkoutEvent {
        WorkoutEvent(kind: kind, dueAt: .seconds(due), isLate: now - due > configuration.lateThreshold.seconds)
    }

    /// Advances the workout to `time`, returning every event due on the way.
    @discardableResult
    private mutating func process(until time: Double) -> [WorkoutEvent] {
        let now = max(time, clock)
        var events: [WorkoutEvent] = []
        if state == .countingDown {
            processCountdown(until: now, events: &events)
        }
        if state == .running {
            processRunning(until: now, events: &events)
        }
        clock = now
        syncRecord()
        return events
    }

    private mutating func processCountdown(until now: Double, events: inout [WorkoutEvent]) {
        guard let start = countdownStart else { return }
        let length = configuration.countdownSeconds
        while nextCountdownTick < length {
            let due = start + Double(nextCountdownTick)
            guard due <= now else { return }
            events.append(event(.countdown(length - nextCountdownTick), due: due, now: now))
            nextCountdownTick += 1
        }
        let startTime = start + Double(length)
        guard startTime <= now else { return }
        state = .running
        clock = startTime
        runStart = startTime
        record.startedAt = runStartDate
        events.append(event(.started(inclinePercent: currentIncline), due: startTime, now: now))
    }

    private mutating func processRunning(until now: Double, events: inout [WorkoutEvent]) {
        let transitions = self.transitions
        let metersPerSecond = speed.metersPerSecond
        let warningLead = configuration.warningLead.seconds

        while state == .running {
            // Warn if the runner is inside the next change's warning window and hasn't been warned yet. Entering
            // the window late (after starting, resuming, or speeding up) warns only if enough time is left.
            if nextTransition < transitions.count, warnedTransition != nextTransition {
                let transition = transitions[nextTransition]
                let secondsToChange = (transition.distance - distance) / metersPerSecond
                if secondsToChange <= warningLead + 1e-9 {
                    warnedTransition = nextTransition
                    if secondsToChange >= configuration.minimumWarningLead.seconds
                        && !isSkippedFinalChange(nextTransition, transitions: transitions)
                    {
                        let kind = WorkoutEvent.Kind.upcomingChange(
                            fromPercent: currentIncline, toPercent: transition.toPercent,
                            secondsRemaining: secondsToChange)
                        events.append(event(kind, due: clock, now: now))
                    }
                }
            }

            // Find the earliest of: entering the next warning window, reaching the next change, finishing.
            var nextTime = clock + (segmentLength - distance) / metersPerSecond
            var nextStep = Step.finish
            if nextTransition < transitions.count {
                let transition = transitions[nextTransition]
                let reachTime = clock + (transition.distance - distance) / metersPerSecond
                if reachTime < nextTime {
                    nextTime = reachTime
                    nextStep = .reachChange
                }
                if warnedTransition != nextTransition {
                    let warnTime = reachTime - warningLead
                    if warnTime > clock && warnTime < nextTime {
                        nextTime = warnTime
                        nextStep = .enterWarningWindow
                    }
                }
            }

            guard nextTime <= now else {
                run(for: now - clock)
                return
            }
            run(for: nextTime - clock)

            switch nextStep {
            case .enterWarningWindow:
                continue
            case .reachChange:
                let transition = transitions[nextTransition]
                distance = transition.distance
                if !isSkippedFinalChange(nextTransition, transitions: transitions) {
                    let kind = WorkoutEvent.Kind.inclineChange(
                        fromPercent: currentIncline, toPercent: transition.toPercent)
                    events.append(event(kind, due: clock, now: now))
                    record.inclineChanges.append(
                        .init(distanceMeters: distance, fromPercent: currentIncline, toPercent: transition.toPercent))
                    currentIncline = transition.toPercent
                }
                nextTransition += 1
            case .finish:
                distance = segmentLength
                state = .finished
                record.outcome = .finished
                record.endedAt = wallClockDate(at: clock)
                events.append(event(.finished, due: clock, now: now))
            }
        }
    }

    private enum Step {
        case enterWarningWindow, reachChange, finish
    }

    /// Runs at the current speed for `seconds`.
    private mutating func run(for seconds: Double) {
        guard seconds > 0 else { return }
        distance = min(distance + speed.metersPerSecond * seconds, segmentLength)
        activeSeconds += seconds
        clock += seconds
    }

    private mutating func closePause() {
        guard let start = pauseStartTime, let pausedAt = pauseStartDistance else { return }
        record.pauses.append(.init(distanceMeters: pausedAt, duration: .seconds(clock - start)))
        pauseStartTime = nil
        pauseStartDistance = nil
    }

    private func wallClockDate(at time: Double) -> Date? {
        guard let runStart, let runStartDate else { return nil }
        return runStartDate.addingTimeInterval(time - runStart)
    }

    private mutating func syncRecord() {
        record.activeDuration = .seconds(activeSeconds)
        record.distanceMeters = distance
    }

    private func currentSnapshot() -> WorkoutSnapshot {
        let transitions = self.transitions
        var nextChange: WorkoutSnapshot.NextChange?
        if !state.isOver, nextTransition < transitions.count,
            !isSkippedFinalChange(nextTransition, transitions: transitions)
        {
            let away = transitions[nextTransition].distance - distance
            nextChange = .init(
                inclinePercent: transitions[nextTransition].toPercent, distanceMeters: away,
                timeRemaining: .seconds(away / speed.metersPerSecond))
        }
        var countdownRemaining: Int?
        if state == .countingDown, let start = countdownStart {
            let left = Double(configuration.countdownSeconds) - (clock - start)
            countdownRemaining = max(1, Int(left.rounded(.up)))
        }
        return WorkoutSnapshot(
            state: state, countdownRemaining: countdownRemaining, activeElapsed: .seconds(activeSeconds),
            distanceMeters: distance, coursePositionMeters: profile.segment.startMeters + distance,
            remainingMeters: segmentLength - distance, currentInclinePercent: currentIncline, nextChange: nextChange,
            speed: speed, fractionComplete: distance / segmentLength)
    }
}
