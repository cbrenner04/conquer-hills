import Foundation
import Testing

@testable import CourseKit

@Suite("Validating course files")
struct CourseValidationTests {
    // MARK: Identity

    @Test("The id must be a lowercase slug", arguments: ["Fixture", "fixture_course", "fixture course", ""])
    func invalidID(id: String) throws {
        let problems = try Fixture.problems(
            Fixture.json().setting("id", to: id), fileName: id + CourseLoader.fileSuffix)

        #expect(problems.contains(.invalidID(id)))
    }

    @Test("The id must match the file name")
    func idMatchesFileName() throws {
        let problems = try Fixture.problems(Fixture.json(), fileName: "other.course.json")

        #expect(problems == [.idDoesNotMatchFileName(id: "fixture", fileName: "other.course.json")])
    }

    @Test("The name must not be empty")
    func emptyName() throws {
        #expect(try Fixture.problems(Fixture.json().setting("name", to: "")) == [.emptyName])
    }

    // MARK: Distance

    @Test("The distance must be positive", arguments: [0.0, -100.0])
    func invalidDistance(distance: Double) throws {
        let problems = try Fixture.problems(Fixture.json().setting("distanceMeters", to: distance))

        #expect(problems.contains(.invalidDistance(distance)))
    }

    // MARK: Incline changes

    @Test("There must be at least one incline change")
    func noInclineChanges() throws {
        #expect(try Fixture.problems(Fixture.json(changes: [])) == [.noInclineChanges])
    }

    @Test("The first incline change must be at the start")
    func firstChangeAtStart() throws {
        let problems = try Fixture.problems(Fixture.json(changes: [(100, 1)]))

        #expect(problems == [.firstInclineChangeNotAtStart(atMeters: 100)])
    }

    @Test("Incline change positions must strictly increase")
    func positionsIncrease() throws {
        let equal = try Fixture.problems(Fixture.json(changes: [(0, 1), (500, 2), (500, 3)]))
        let decreasing = try Fixture.problems(Fixture.json(changes: [(0, 1), (500, 2), (400, 3)]))

        #expect(equal == [.inclineChangeNotAfterPrevious(index: 2)])
        #expect(decreasing == [.inclineChangeNotAfterPrevious(index: 2)])
    }

    @Test("Incline changes must be before the finish")
    func changesBeforeFinish() throws {
        let problems = try Fixture.problems(Fixture.json(changes: [(0, 1), (2400, 2)]))

        #expect(problems == [.inclineChangeNotBeforeFinish(index: 1)])
    }

    @Test("Inclines beyond ±30% are rejected", arguments: [30.5, -31.0])
    func inclineOutOfRange(incline: Double) throws {
        let problems = try Fixture.problems(Fixture.json(changes: [(0, incline)]))

        #expect(problems == [.inclineOutOfRange(index: 0, inclinePercent: incline)])
    }

    @Test("Inclines of exactly ±30% are allowed", arguments: [30.0, -30.0])
    func inclineAtLimit(incline: Double) throws {
        #expect(throws: Never.self) { try Fixture.course(Fixture.json(changes: [(0, incline)])) }
    }

    @Test("Inclines must be multiples of 0.5%", arguments: [0.3, 1.25, -2.1])
    func inclineNotHalfPercent(incline: Double) throws {
        let problems = try Fixture.problems(Fixture.json(changes: [(0, incline)]))

        #expect(problems == [.inclineNotHalfPercent(index: 0, inclinePercent: incline)])
    }

    @Test("Consecutive incline changes must differ")
    func repeatedIncline() throws {
        let problems = try Fixture.problems(Fixture.json(changes: [(0, 1), (100, 1)]))

        #expect(problems == [.inclineRepeatsPrevious(index: 1)])
    }

    // MARK: Elevation profile

    @Test("Sample spacing must be positive")
    func invalidSpacing() throws {
        let problems = try Fixture.problems(Fixture.json().setting("elevationProfile.sampleSpacingMeters", to: 0))

        #expect(problems == [.invalidSampleSpacing(0)])
    }

    @Test("The number of elevation samples must match the distance and spacing")
    func sampleCountMismatch() throws {
        let json = Fixture.json().setting("elevationProfile.elevationsMeters", to: Array(repeating: 5.0, count: 24))

        #expect(try Fixture.problems(json) == [.elevationSampleCountMismatch(expected: 25, actual: 24)])
    }

    @Test(
        "Expected sample count includes the finish",
        arguments: [(2400.0, 100.0, 25), (42195.0, 100.0, 423), (50.0, 100.0, 2), (300.0, 100.0, 4)])
    func expectedSampleCount(distance: Double, spacing: Double, expected: Int) {
        #expect(CourseFile.expectedSampleCount(distanceMeters: distance, spacingMeters: spacing) == expected)
    }

    @Test("Elevations must be finite (for files built in code)")
    func nonFiniteElevation() throws {
        var file = try JSONDecoder().decode(CourseFile.self, from: Fixture.data(Fixture.json()))
        file.elevationProfile.elevationsMeters[3] = .nan

        #expect(file.problems(fileName: Fixture.fileName) == [.elevationNotFinite(index: 3)])
    }

    // MARK: Stats

    @Test("Elevation gain and loss must not be negative")
    func negativeGain() throws {
        let problems = try Fixture.problems(Fixture.json().setting("stats.elevationLossMeters", to: -1.0))

        #expect(problems == [.invalidStats("gain and loss must not be negative")])
    }

    @Test("Minimum elevation must not exceed maximum")
    func minimumAboveMaximum() throws {
        let problems = try Fixture.problems(Fixture.json().setting("stats.minimumElevationMeters", to: 50.0))

        #expect(problems == [.invalidStats("minimum elevation exceeds maximum")])
    }

    // MARK: Segments

    @Test("A valid curated segment is accepted")
    func validSegment() throws {
        let course = try Fixture.course(Fixture.json(segments: [Fixture.segment(start: 0, end: 2400)]))

        #expect(course.curatedSegments.map(\.id) == ["hill"])
    }

    @Test("Segment ids must be non-empty and unique")
    func segmentIDs() throws {
        let problems = try Fixture.problems(
            Fixture.json(segments: [
                Fixture.segment(id: "", start: 0, end: 100),
                Fixture.segment(id: "hill", start: 0, end: 100),
                Fixture.segment(id: "hill", start: 100, end: 200),
            ]))

        #expect(problems == [.emptySegmentID(index: 0), .duplicateSegmentID("hill")])
    }

    @Test("Segment names must not be empty")
    func segmentName() throws {
        let problems = try Fixture.problems(Fixture.json(segments: [Fixture.segment(name: "", start: 0, end: 100)]))

        #expect(problems == [.emptySegmentName(index: 0)])
    }

    @Test(
        "Segments must lie within the course with start before end",
        arguments: [(-1.0, 100.0), (100.0, 100.0), (200.0, 100.0), (0.0, 2401.0)])
    func segmentRange(start: Double, end: Double) throws {
        let problems = try Fixture.problems(Fixture.json(segments: [Fixture.segment(start: start, end: end)]))

        #expect(problems == [.segmentOutOfRange(index: 0)])
    }

    // MARK: Reporting

    @Test("Every problem in a file is reported, not just the first")
    func reportsAllProblems() throws {
        let json = Fixture.json(changes: [(0, 1), (100, 1)], segments: [Fixture.segment(name: "", start: 0, end: 100)])
            .setting("name", to: "")
            .setting("stats.minimumElevationMeters", to: 50.0)

        #expect(
            try Fixture.problems(json) == [
                .emptyName,
                .inclineRepeatsPrevious(index: 1),
                .invalidStats("minimum elevation exceeds maximum"),
                .emptySegmentName(index: 0),
            ])
    }

    @Test("Failures describe the file and each problem")
    func failureDescription() {
        let failure = CourseValidationFailure(
            fileName: "x.course.json", problems: [.emptyName, .missingField(path: "stats")])

        #expect(failure.description == "x.course.json: name is empty; missing field stats")
    }
}
