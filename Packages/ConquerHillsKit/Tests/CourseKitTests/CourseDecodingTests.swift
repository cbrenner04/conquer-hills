import Foundation
import Testing

@testable import CourseKit

@Suite("Decoding course files")
struct CourseDecodingTests {
    @Test("A valid file decodes into a course")
    func validFileDecodes() throws {
        let course = try Fixture.course()

        #expect(course.id == "fixture")
        #expect(course.name == "Fixture Course")
        #expect(course.edition == "2026")
        #expect(course.location == "Testville")
        #expect(course.distanceMeters == 2400)
        #expect(!course.isDevelopmentOnly)
        #expect(course.description == "A course for tests.")
        #expect(
            course.source.route
                == SourceReference(name: "Route source", url: "https://example.com/route", license: "Test license"))
        #expect(course.source.elevation.kind == .modeled)
        #expect(course.source.elevation.url == nil)
        #expect(course.source.attribution == "© Test")
        #expect(course.source.notes == nil)
        #expect(!course.source.isVerified)
        #expect(course.processing.parameters == ["window": "200"])
        #expect(course.stats.elevationGainMeters == 10)
        #expect(course.curatedSegments.isEmpty)
    }

    @Test("Elevation samples are evenly spaced, with the last at the finish")
    func elevationSampleDistances() throws {
        let course = try Fixture.course(Fixture.json(distance: 250, changes: [(0, 1)]))

        #expect(course.elevationProfile.map(\.distanceMeters) == [0, 100, 200, 250])
    }

    @Test("Incline changes become contiguous intervals ending at the finish")
    func inclineIntervalsFromChanges() throws {
        let course = try Fixture.course()

        #expect(
            course.inclineIntervals == [
                CourseInclineInterval(startMeters: 0, endMeters: 1000, inclinePercent: 1),
                CourseInclineInterval(startMeters: 1000, endMeters: 2000, inclinePercent: -2),
                CourseInclineInterval(startMeters: 2000, endMeters: 2400, inclinePercent: 3),
            ])
    }

    @Test("A single incline change covers the whole course")
    func singleInclineChange() throws {
        let course = try Fixture.course(Fixture.json(changes: [(0, 0.5)]))

        #expect(
            course.inclineIntervals == [CourseInclineInterval(startMeters: 0, endMeters: 2400, inclinePercent: 0.5)])
    }

    @Test("The file format round-trips through encoding")
    func roundTrip() throws {
        let original = try JSONDecoder().decode(CourseFile.self, from: Fixture.data(Fixture.json()))
        let reencoded = try JSONDecoder().decode(CourseFile.self, from: JSONEncoder().encode(original))

        #expect(reencoded == original)
    }

    @Test("Optional fields may be omitted or null")
    func optionalFields() throws {
        var json = Fixture.json()
        for path in ["description", "source.attribution", "source.notes", "source.route.url", "source.elevation.url"] {
            json = json.setting(path, to: nil)
        }
        #expect(try Fixture.course(json).description == nil)

        json = json.setting("description", to: NSNull())
        #expect(try Fixture.course(json).description == nil)
    }

    @Test("Processing parameters accept any keys")
    func freeFormParameters() throws {
        let json = Fixture.json().setting("processing.parameters", to: ["anything": "goes", "more": "keys"])

        #expect(try Fixture.course(json).processing.parameters.count == 2)
    }

    @Test("An unknown top-level field is rejected")
    func unknownTopLevelField() throws {
        let problems = try Fixture.problems(Fixture.json().setting("distanceMiles", to: 1.5))

        #expect(problems == [.unknownField(path: "distanceMiles")])
    }

    @Test("An unknown nested field is rejected with its path")
    func unknownNestedField() throws {
        let problems = try Fixture.problems(Fixture.json().setting("source.route.licence", to: "typo"))

        #expect(problems == [.unknownField(path: "source.route.licence")])
    }

    @Test("An unknown field inside an array element is rejected with its index")
    func unknownFieldInArray() throws {
        let changes: [[String: Any]] = [["atMeters": 0, "inclinePercent": 1, "grade": 1]]
        let problems = try Fixture.problems(Fixture.json().setting("inclineChanges", to: changes))

        #expect(problems == [.unknownField(path: "inclineChanges[0].grade")])
    }

    @Test(
        "A missing field is rejected with its path",
        arguments: ["name", "stats.elevationLossMeters", "source.verified"])
    func missingField(path: String) throws {
        let problems = try Fixture.problems(Fixture.json().setting(path, to: nil))

        #expect(problems == [.missingField(path: path)])
    }

    @Test("A missing schema version is reported")
    func missingSchemaVersion() throws {
        let problems = try Fixture.problems(Fixture.json().setting("schemaVersion", to: nil))

        #expect(problems == [.missingField(path: "schemaVersion")])
    }

    @Test("An unsupported schema version is rejected before the rest of the file is decoded")
    func unsupportedSchemaVersion() throws {
        let json = Fixture.json().setting("schemaVersion", to: 2).setting("someNewField", to: true)

        #expect(try Fixture.problems(json) == [.unsupportedSchemaVersion(2)])
    }

    @Test("A value of the wrong type is unreadable, naming the field")
    func typeMismatch() throws {
        let problems = try Fixture.problems(Fixture.json().setting("distanceMeters", to: "far"))

        guard case .unreadable(let detail) = try #require(problems.first) else {
            Issue.record("Expected .unreadable, got \(problems)")
            return
        }
        #expect(detail.contains("distanceMeters"))
    }

    @Test("An unknown elevation kind is unreadable")
    func unknownElevationKind() throws {
        let problems = try Fixture.problems(Fixture.json().setting("source.elevation.kind", to: "guessed"))

        guard case .unreadable(let detail) = try #require(problems.first) else {
            Issue.record("Expected .unreadable, got \(problems)")
            return
        }
        #expect(detail.contains("source.elevation.kind"))
    }

    @Test("Malformed JSON is unreadable")
    func malformedJSON() {
        let result = CourseLoader.load(Data("{".utf8), fileName: Fixture.fileName)

        guard case .failure(let failure) = result, case .unreadable = failure.problems.first else {
            Issue.record("Expected an unreadable failure, got \(result)")
            return
        }
    }
}
