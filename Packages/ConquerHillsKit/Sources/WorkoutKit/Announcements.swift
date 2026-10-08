import Foundation

/// Something to say to the runner, with what kind of prompt it is so the app can pair it with a flash or haptic.
public struct Announcement: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case countdown
        case start
        case warning
        /// An incline change; `isUp` is true when the incline increases.
        case change(isUp: Bool)
        case resume
        case finish
        /// After a gap: the incline the runner should be at now.
        case catchUp
    }

    public let kind: Kind
    /// What to speak.
    public let text: String

    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }
}

/// Spoken wording for workout events.
///
/// Inclines are given as the target first, with the direction: the absolute number is what the treadmill's
/// display shows, so it is the quickest to match.
public enum PromptWording {
    /// An incline for speech: "6.5" or "1" (no trailing ".0").
    public static func spokenIncline(_ percent: Double) -> String {
        percent == percent.rounded() ? String(Int(percent)) : String(format: "%.1f", percent)
    }

    public static func announcement(for kind: WorkoutEvent.Kind) -> Announcement {
        switch kind {
        case .countdown(let seconds):
            return Announcement(kind: .countdown, text: "\(seconds)")
        case .started(let incline):
            return Announcement(kind: .start, text: "Go. Incline \(spokenIncline(incline)) percent.")
        case .upcomingChange(let from, let to, let secondsRemaining):
            let direction = to > from ? "up" : "down"
            let seconds = Int(secondsRemaining.rounded())
            return Announcement(
                kind: .warning,
                text: "Incline \(direction) to \(spokenIncline(to)) percent in \(seconds) seconds.")
        case .inclineChange(let from, let to):
            let isUp = to > from
            return Announcement(
                kind: .change(isUp: isUp), text: "\(isUp ? "Up" : "Down") to \(spokenIncline(to)) percent.")
        case .resumed(let incline):
            return Announcement(kind: .resume, text: "Resumed. Incline \(spokenIncline(incline)) percent.")
        case .finished:
            return Announcement(kind: .finish, text: "Course complete.")
        }
    }

    public static func catchUp(inclinePercent: Double) -> Announcement {
        Announcement(kind: .catchUp, text: "Incline now \(spokenIncline(inclinePercent)) percent.")
    }
}

/// Decides what to say for a batch of events returned by one engine call.
public enum AnnouncementPolicy {
    /// Events on time are announced in order. Late events (the app wasn't checking, e.g. during a phone call) are
    /// never read out as a backlog: if any of them changed the incline, the runner is told only the incline they
    /// should be at now, unless an on-time event already says so. A late finish is still announced.
    public static func announcements(for events: [WorkoutEvent], currentInclinePercent: Double) -> [Announcement] {
        let late = events.filter(\.isLate)
        let onTime = events.filter { !$0.isLate }

        if late.contains(where: { $0.kind == .finished }) {
            return [PromptWording.announcement(for: .finished)]
        }

        var result: [Announcement] = []
        let lateChangedIncline = late.contains { $0.kind.setsIncline }
        let onTimeSetsIncline = onTime.contains { $0.kind.setsIncline }
        if lateChangedIncline && !onTimeSetsIncline {
            result.append(PromptWording.catchUp(inclinePercent: currentInclinePercent))
        }
        result += onTime.map { PromptWording.announcement(for: $0.kind) }
        return result
    }
}

extension WorkoutEvent.Kind {
    /// Whether the event tells the runner an incline to be at.
    var setsIncline: Bool {
        switch self {
        case .started, .inclineChange, .resumed: true
        case .countdown, .upcomingChange, .finished: false
        }
    }
}
