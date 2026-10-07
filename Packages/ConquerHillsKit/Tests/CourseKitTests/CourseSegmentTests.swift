import Testing

@testable import CourseKit

@Suite("Course segments")
struct CourseSegmentTests {
    @Test("A marathon gets all five standard segments, in order")
    func marathonStandardSegments() throws {
        let course = try Fixture.course(Fixture.json(distance: 42195))

        let segments = course.standardSegments
        #expect(segments.map(\.id) == ["full-course", "first-half", "second-half", "first-5k", "final-5k"])
        #expect(segments.map(\.name) == ["Full course", "First half", "Second half", "First 5K", "Final 5K"])
        #expect(segments.map(\.kind) == [.fullCourse, .standard, .standard, .standard, .standard])
        #expect(segments.map(\.startMeters) == [0, 0, 21097.5, 0, 37195])
        #expect(segments.map(\.endMeters) == [42195, 21097.5, 42195, 5000, 42195])
    }

    @Test("A short course gets only the full course")
    func shortCourse() throws {
        let course = try Fixture.course()

        #expect(course.standardSegments == [course.fullCourseSegment])
        #expect(course.fullCourseSegment.distanceMeters == 2400)
    }

    @Test("Halves and 5Ks start at exactly 10 km", arguments: [(9_999.0, 1), (10_000.0, 5)])
    func tenKilometerBoundary(distance: Double, expectedCount: Int) throws {
        let course = try Fixture.course(Fixture.json(distance: distance, changes: [(0, 0)]))

        #expect(course.standardSegments.count == expectedCount)
    }

    @Test("Predefined segments are the standard ones followed by curated ones")
    func predefinedSegments() throws {
        let course = try Fixture.course(
            Fixture.json(
                distance: 42195, segments: [Fixture.segment(id: "hills", name: "Hills", start: 30000, end: 34000)])
        )

        let predefined = course.predefinedSegments
        #expect(predefined.count == 6)
        #expect(predefined.last?.id == "hills")
        #expect(predefined.last?.kind == .curated)
        #expect(predefined.last?.distanceMeters == 4000)
    }

    @Test("A custom segment within the course is created")
    func validCustomSegment() throws {
        let course = try Fixture.course()

        let segment = try #require(course.customSegment(startMeters: 500, endMeters: 1500))
        #expect(segment.kind == .custom)
        #expect(segment.name == nil)
        #expect(segment.distanceMeters == 1000)
        #expect(course.contains(segment))
    }

    @Test(
        "An invalid custom segment is rejected",
        arguments: [(-1.0, 100.0), (500.0, 500.0), (600.0, 500.0), (0.0, 2400.5)])
    func invalidCustomSegment(start: Double, end: Double) throws {
        let course = try Fixture.course()

        #expect(course.customSegment(startMeters: start, endMeters: end) == nil)
    }

    @Test("A segment from a longer course is not contained in a shorter one")
    func containsChecksBounds() throws {
        let marathon = try Fixture.course(Fixture.json(distance: 42195))
        let short = try Fixture.course()

        #expect(!short.contains(marathon.fullCourseSegment))
        #expect(marathon.contains(short.fullCourseSegment))
    }
}
