import Foundation
import Testing

@testable import CourseKit

@Suite("Loading courses from a directory")
struct CourseLoaderTests {
    /// The app's bundled course files, found relative to this source file.
    static let bundledCoursesDirectory = URL(filePath: #filePath)
        .deletingLastPathComponent()  // CourseKitTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // ConquerHillsKit
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()  // repository root
        .appending(path: "App/Resources/Courses")

    @Test("Every bundled course file is valid")
    func bundledCoursesAreValid() {
        let (courses, failures) = CourseLoader.loadAll(in: Self.bundledCoursesDirectory)

        #expect(failures.isEmpty, "\(failures.map(\.description))")
        #expect(!courses.isEmpty, "No courses found in \(Self.bundledCoursesDirectory.path)")
    }

    @Test("The bundled Test Hills course matches spec 03")
    func testHillsCourse() throws {
        let (courses, _) = CourseLoader.loadAll(in: Self.bundledCoursesDirectory)
        let course = try #require(courses.first { $0.id == "test-hills" })

        #expect(course.isDevelopmentOnly)
        #expect(course.distanceMeters == 2400)
        #expect(
            course.stats
                == CourseStats(
                    elevationGainMeters: 75, elevationLossMeters: 8, minimumElevationMeters: 10,
                    maximumElevationMeters: 77))
        #expect(course.standardSegments == [course.fullCourseSegment])
        #expect(course.inclineIntervals == (try Fixture.testHills()).inclineIntervals)
        #expect(course.elevationProfile.last == ElevationSample(distanceMeters: 2400, elevationMeters: 77))
    }

    @Test("Valid files load, invalid ones are reported, and other files are ignored")
    func mixedDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "CourseLoaderTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let valid = Fixture.json().setting("id", to: "b-valid")
        let invalid = Fixture.json().setting("id", to: "a-invalid").setting("name", to: "")
        try Fixture.data(valid).write(to: directory.appending(path: "b-valid.course.json"))
        try Fixture.data(invalid).write(to: directory.appending(path: "a-invalid.course.json"))
        try Data("not a course".utf8).write(to: directory.appending(path: "README.md"))

        let (courses, failures) = CourseLoader.loadAll(in: directory)

        #expect(courses.map(\.id) == ["b-valid"])
        #expect(failures == [CourseValidationFailure(fileName: "a-invalid.course.json", problems: [.emptyName])])
    }

    @Test("A missing directory is reported as a failure")
    func missingDirectory() {
        let (courses, failures) = CourseLoader.loadAll(in: URL(filePath: "/nonexistent-\(UUID())"))

        #expect(courses.isEmpty)
        #expect(failures.count == 1)
    }
}
