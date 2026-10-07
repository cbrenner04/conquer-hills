import Testing

@testable import CourseKit

@Suite("Treadmill profiles")
struct TreadmillProfileTests {
    /// Shorthand for expected intervals: (start, end, incline).
    private func intervals(_ values: [(Double, Double, Double)]) -> [TreadmillInterval] {
        values.map { TreadmillInterval(startMeters: $0.0, endMeters: $0.1, inclinePercent: $0.2) }
    }

    @Test("Full course with Peloton Tread defaults: clamped, merged, and capped at 12.5%")
    func fullCourseDefaults() throws {
        let course = try Fixture.testHills()

        let profile = TreadmillProfile(course: course, segment: course.fullCourseSegment)

        #expect(profile.settings == .pelotonTread)
        #expect(
            profile.intervals
                == intervals([
                    (0, 200, 1), (200, 400, 3), (400, 600, 6.5), (600, 700, 2), (700, 1100, 0), (1100, 1300, 0.5),
                    (1300, 1500, 12.5), (1500, 1700, 4.5), (1700, 2000, 0), (2000, 2400, 2.5),
                ]))
    }

    @Test("Tread+ settings cap at 15%")
    func treadPlus() throws {
        let course = try Fixture.testHills()

        let profile = TreadmillProfile(course: course, segment: course.fullCourseSegment, settings: .pelotonTreadPlus)

        #expect(profile.intervals.first { $0.startMeters == 1300 }?.inclinePercent == 15)
    }

    @Test("A 1% baseline lifts every incline, and shallow downhills reach 0% instead of vanishing")
    func baseline() throws {
        let course = try Fixture.testHills()

        let profile = TreadmillProfile(
            course: course, segment: course.fullCourseSegment, settings: TreadmillSettings(baselinePercent: 1))

        #expect(
            profile.intervals
                == intervals([
                    (0, 200, 2), (200, 400, 4), (400, 600, 7.5), (600, 700, 3), (700, 1100, 0), (1100, 1300, 1.5),
                    (1300, 1500, 12.5), (1500, 1700, 5.5), (1700, 2000, 1), (2000, 2400, 3.5),
                ]))
    }

    @Test("Raising the minimum clamps and merges a run of neighbours")
    func minimumClampMergesChain() throws {
        let course = try Fixture.testHills()

        let profile = TreadmillProfile(
            course: course, segment: course.fullCourseSegment, settings: TreadmillSettings(minimumPercent: 2))

        #expect(
            profile.intervals
                == intervals([
                    (0, 200, 2), (200, 400, 3), (400, 600, 6.5), (600, 1300, 2), (1300, 1500, 12.5),
                    (1500, 1700, 4.5), (1700, 2000, 2), (2000, 2400, 2.5),
                ]))
    }

    @Test("A segment starting and ending mid-interval is cut to the segment")
    func midIntervalSegment() throws {
        let course = try Fixture.testHills()
        let segment = try #require(course.customSegment(startMeters: 250, endMeters: 1050))

        let profile = TreadmillProfile(course: course, segment: segment)

        #expect(profile.intervals == intervals([(250, 400, 3), (400, 600, 6.5), (600, 700, 2), (700, 1050, 0)]))
    }

    @Test("A segment exactly on interval boundaries takes only those intervals")
    func boundarySegment() throws {
        let course = try Fixture.testHills()
        let segment = try #require(course.customSegment(startMeters: 200, endMeters: 600))

        let profile = TreadmillProfile(course: course, segment: segment)

        #expect(profile.intervals == intervals([(200, 400, 3), (400, 600, 6.5)]))
    }

    @Test("A segment inside a single interval has one interval")
    func segmentInsideInterval() throws {
        let course = try Fixture.testHills()
        let segment = try #require(course.customSegment(startMeters: 2100, endMeters: 2300))

        let profile = TreadmillProfile(course: course, segment: segment)

        #expect(profile.intervals == intervals([(2100, 2300, 2.5)]))
    }

    @Test("Rounding to a 1% increment goes half away from zero")
    func wholePercentIncrement() throws {
        let course = try Fixture.testHills()

        let profile = TreadmillProfile(
            course: course, segment: course.fullCourseSegment, settings: TreadmillSettings(incrementPercent: 1))

        #expect(
            profile.intervals
                == intervals([
                    (0, 200, 1), (200, 400, 3), (400, 600, 7), (600, 700, 2), (700, 1100, 0), (1100, 1300, 1),
                    (1300, 1500, 12.5), (1500, 1700, 5), (1700, 2000, 0), (2000, 2400, 3),
                ]))
    }

    @Test(
        "Profiles are contiguous, cover the segment exactly, and have no equal neighbours",
        arguments: [(0.0, 2400.0), (250.0, 1050.0), (650.0, 1150.0), (1999.0, 2001.0), (0.0, 1.0)])
    func profileInvariants(start: Double, end: Double) throws {
        let course = try Fixture.testHills()
        let segment = try #require(course.customSegment(startMeters: start, endMeters: end))

        let profile = TreadmillProfile(course: course, segment: segment)

        let intervals = profile.intervals
        #expect(intervals.first?.startMeters == start)
        #expect(intervals.last?.endMeters == end)
        for (previous, next) in zip(intervals, intervals.dropFirst()) {
            #expect(previous.endMeters == next.startMeters)
            #expect(previous.inclinePercent != next.inclinePercent)
        }
        #expect(intervals.allSatisfy { $0.startMeters < $0.endMeters })
    }
}

@Suite("Treadmill settings")
struct TreadmillSettingsTests {
    @Test("Peloton presets match the published specs")
    func presets() {
        #expect(
            TreadmillSettings.pelotonTread
                == TreadmillSettings(baselinePercent: 0, minimumPercent: 0, maximumPercent: 12.5, incrementPercent: 0.5)
        )
        #expect(TreadmillSettings.pelotonTreadPlus.maximumPercent == 15)
        #expect(TreadmillSettings() == .pelotonTread)
    }

    @Test(
        "Course incline maps to treadmill incline",
        arguments: [
            (0.25, 0.5),  // half away from zero
            (-0.25, 0.0),  // rounds to -0.5, clamps to 0
            (3.0, 3.0),
            (12.5, 12.5),
            (12.75, 12.5),  // rounds to 13, clamps to the maximum
            (-8.0, 0.0),
        ])
    func mapping(courseIncline: Double, expected: Double) {
        #expect(TreadmillSettings.pelotonTread.treadmillIncline(forCourseIncline: courseIncline) == expected)
    }

    @Test("Rounding happens before clamping, so the result never exceeds the maximum")
    func roundsBeforeClamping() {
        let settings = TreadmillSettings(incrementPercent: 1)

        #expect(settings.treadmillIncline(forCourseIncline: 12.4) == 12)
        #expect(settings.treadmillIncline(forCourseIncline: 12.6) == 12.5)
    }

    @Test("Zero is never negative zero")
    func noNegativeZero() {
        let incline = TreadmillSettings(minimumPercent: -3).treadmillIncline(forCourseIncline: -0.2)

        #expect(incline == 0)
        #expect(incline.sign == .plus)
    }
}
