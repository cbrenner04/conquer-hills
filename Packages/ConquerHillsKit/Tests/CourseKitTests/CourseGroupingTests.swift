import Foundation
import Testing

@testable import CourseKit

@Suite("Course list grouping")
struct CourseGroupingTests {
    func course(_ id: String, _ name: String, _ location: String, meters: Double = 42_195) throws -> Course {
        var json = Fixture.json(distance: meters, changes: [(0, 1)])
        json["id"] = id
        json["name"] = name
        json["location"] = location
        return try Fixture.load(json, fileName: "\(id).course.json").get()
    }

    @Test("Distance classes split at 40,000, 20,000, 14,000 and 9,500 m")
    func distanceBoundaries() {
        #expect(CourseDistanceClass(meters: 42_195) == .marathon)
        #expect(CourseDistanceClass(meters: 40_000) == .marathon)
        #expect(CourseDistanceClass(meters: 39_999) == .halfMarathon)
        #expect(CourseDistanceClass(meters: 21_097) == .halfMarathon)
        #expect(CourseDistanceClass(meters: 19_999) == .fifteenK)
        #expect(CourseDistanceClass(meters: 14_000) == .fifteenK)
        #expect(CourseDistanceClass(meters: 12_000) == .tenK)
        #expect(CourseDistanceClass(meters: 9_500) == .tenK)
        #expect(CourseDistanceClass(meters: 7_640) == .short)
    }

    @Test("Country and city come from the location's last comma")
    func countryAndCity() {
        #expect(CourseRegion.country(of: "Hopkinton to Boston, Massachusetts, USA") == "United States")
        #expect(
            CourseRegion.city(of: "Hopkinton to Boston, Massachusetts, USA") == "Hopkinton to Boston, Massachusetts")
        #expect(CourseRegion.country(of: "Tokyo, Japan") == "Japan")
        #expect(CourseRegion.city(of: "Tokyo, Japan") == "Tokyo")
        #expect(CourseRegion.country(of: "Leadville, Colorado") == nil)
        #expect(CourseRegion.city(of: "Development only") == "Development only")
    }

    @Test("By distance: longest group first, each sorted by name")
    func byDistance() throws {
        let courses = [
            try course("b", "Boston", "Boston, Massachusetts, USA"),
            try course("p", "Peachtree", "Atlanta, Georgia, USA", meters: 10_000),
            try course("a", "Atlanta Half", "Atlanta, Georgia, USA", meters: 21_097),
            try course("t", "Tokyo", "Tokyo, Japan"),
        ]

        let sections = CourseGrouping.sections(courses, by: .distance)

        #expect(sections.map(\.title) == ["Marathon", "Half marathon", "10K to 8 miles"])
        #expect(sections[0].courses.map(\.name) == ["Boston", "Tokyo"])
    }

    @Test("By region: United States first, other countries alphabetically, unknown last")
    func byRegion() throws {
        let courses = [
            try course("t", "Tokyo", "Tokyo, Japan"),
            try course("l", "London", "London, United Kingdom"),
            try course("x", "Test Hills", "Development only", meters: 2_400),
            try course("c", "Chicago", "Chicago, Illinois, USA"),
            try course("b", "Berlin", "Berlin, Germany"),
        ]

        let sections = CourseGrouping.sections(courses, by: .region)

        #expect(sections.map(\.title) == ["United States", "Germany", "Japan", "United Kingdom", "Other"])
    }

    @Test("Search matches name or location, ignoring case and accents; empty groups disappear")
    func search() throws {
        let courses = [
            try course("b", "Boston Marathon", "Hopkinton to Boston, Massachusetts, USA"),
            try course("c", "Cape Town Marathon", "Green Point, Cape Town, South Africa"),
            try course("z", "Zürich Run", "Zürich, Switzerland", meters: 10_000),
        ]

        #expect(
            CourseGrouping.sections(courses, by: .distance, matching: "boston").flatMap(\.courses).map(\.id) == ["b"])
        #expect(CourseGrouping.sections(courses, by: .distance, matching: "massachusetts").count == 1)
        #expect(CourseGrouping.sections(courses, by: .region, matching: "zurich").map(\.title) == ["Other"])
        #expect(CourseGrouping.sections(courses, by: .distance, matching: "nowhere").isEmpty)
        #expect(CourseGrouping.sections(courses, by: .distance, matching: "  ").flatMap(\.courses).count == 3)
    }

    @Test("Every bundled course, except development ones, is in a known country")
    func bundledCountries() {
        let (courses, _) = CourseLoader.loadAll(in: CourseLoaderTests.bundledCoursesDirectory)

        for course in courses where !course.isDevelopmentOnly {
            #expect(CourseRegion.country(of: course.location) != nil, "\(course.id): \(course.location)")
        }
    }
}
