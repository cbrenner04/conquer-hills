import Testing

@testable import WorkoutKit

@Suite("Spoken prompts")
struct PromptWordingTests {
    @Test(
        "Each event has target-first wording",
        arguments: [
            (WorkoutEvent.Kind.countdown(3), "3"),
            (.started(inclinePercent: 1), "Go. Incline 1 percent."),
            (
                .upcomingChange(fromPercent: 3, toPercent: 6.5, secondsRemaining: 10),
                "Incline up to 6.5 percent in 10 seconds."
            ),
            (
                .upcomingChange(fromPercent: 6.5, toPercent: 2, secondsRemaining: 7.4),
                "Incline down to 2 percent in 7 seconds."
            ),
            (.inclineChange(fromPercent: 3, toPercent: 6.5), "Up to 6.5 percent."),
            (.inclineChange(fromPercent: 2, toPercent: 0), "Down to 0 percent."),
            (.resumed(inclinePercent: 12.5), "Resumed. Incline 12.5 percent."),
            (.finished, "Course complete."),
        ])
    func wording(kind: WorkoutEvent.Kind, expected: String) {
        #expect(PromptWording.announcement(for: kind).text == expected)
    }

    @Test("Changes carry their direction for the screen flash")
    func changeDirection() {
        #expect(
            PromptWording.announcement(for: .inclineChange(fromPercent: 1, toPercent: 3)).kind == .change(isUp: true))
        #expect(
            PromptWording.announcement(for: .inclineChange(fromPercent: 3, toPercent: 1)).kind == .change(isUp: false))
    }

    @Test(
        "Whole inclines are spoken without a decimal; halves keep it",
        arguments: [(1.0, "1"), (0.0, "0"), (6.5, "6.5"), (12.5, "12.5")])
    func spokenIncline(percent: Double, expected: String) {
        #expect(PromptWording.spokenIncline(percent) == expected)
    }
}

@Suite("Announcement policy")
struct AnnouncementPolicyTests {
    private func event(_ kind: WorkoutEvent.Kind, late: Bool = false) -> WorkoutEvent {
        WorkoutEvent(kind: kind, dueAt: .zero, isLate: late)
    }

    @Test("On-time events are all announced, in order")
    func onTime() {
        let announcements = AnnouncementPolicy.announcements(
            for: [event(.countdown(1)), event(.started(inclinePercent: 1))], currentInclinePercent: 1)

        #expect(announcements.map(\.text) == ["1", "Go. Incline 1 percent."])
    }

    @Test("A late backlog is replaced by the current incline")
    func lateBacklog() {
        let events = [
            event(.upcomingChange(fromPercent: 1, toPercent: 3, secondsRemaining: 10), late: true),
            event(.inclineChange(fromPercent: 1, toPercent: 3), late: true),
            event(.upcomingChange(fromPercent: 3, toPercent: 6.5, secondsRemaining: 10), late: true),
            event(.inclineChange(fromPercent: 3, toPercent: 6.5), late: true),
        ]

        let announcements = AnnouncementPolicy.announcements(for: events, currentInclinePercent: 6.5)

        #expect(announcements == [Announcement(kind: .catchUp, text: "Incline now 6.5 percent.")])
    }

    @Test("Late warnings alone say nothing")
    func lateWarningOnly() {
        let events = [event(.upcomingChange(fromPercent: 1, toPercent: 3, secondsRemaining: 10), late: true)]

        #expect(AnnouncementPolicy.announcements(for: events, currentInclinePercent: 1).isEmpty)
    }

    @Test("No catch-up when an on-time change already gives the new incline")
    func onTimeChangeAfterLate() {
        let events = [
            event(.inclineChange(fromPercent: 1, toPercent: 3), late: true),
            event(.inclineChange(fromPercent: 3, toPercent: 6.5)),
        ]

        let announcements = AnnouncementPolicy.announcements(for: events, currentInclinePercent: 6.5)

        #expect(announcements.map(\.text) == ["Up to 6.5 percent."])
    }

    @Test("Catch-up comes before on-time events that don't set the incline")
    func catchUpThenWarning() {
        let events = [
            event(.inclineChange(fromPercent: 1, toPercent: 3), late: true),
            event(.upcomingChange(fromPercent: 3, toPercent: 6.5, secondsRemaining: 9)),
        ]

        let texts = AnnouncementPolicy.announcements(for: events, currentInclinePercent: 3).map(\.text)

        #expect(texts == ["Incline now 3 percent.", "Incline up to 6.5 percent in 9 seconds."])
    }

    @Test("A late finish is still announced, alone")
    func lateFinish() {
        let events = [event(.inclineChange(fromPercent: 1, toPercent: 3), late: true), event(.finished, late: true)]

        #expect(AnnouncementPolicy.announcements(for: events, currentInclinePercent: 3).map(\.kind) == [.finish])
    }
}

@Suite("Run formatting")
struct RunFormattingTests {
    @Test("Miles to two decimals")
    func miles() {
        #expect(RunFormatting.miles(2400) == "1.49 mi")
        #expect(RunFormatting.miles(42195) == "26.22 mi")
        #expect(RunFormatting.mileNumber(21097.5) == "13.1")
    }

    @Test(
        "Durations as m:ss, or h:mm:ss from an hour",
        arguments: [(0.0, "0:00"), (59.9, "0:59"), (292.0, "4:52"), (3723.0, "1:02:03")])
    func durations(seconds: Double, expected: String) {
        #expect(RunFormatting.duration(.seconds(seconds)) == expected)
    }

    @Test("Speed, incline, and feet")
    func units() {
        #expect(RunFormatting.speed(.mph(6)) == "6.0 mph")
        #expect(RunFormatting.incline(6.5) == "6.5%")
        #expect(RunFormatting.incline(0) == "0.0%")
        #expect(RunFormatting.feet(75) == "246 ft")
    }
}
