import Foundation
import Testing

@testable import CourseKit

@Suite("Writing course files")
struct CourseFileWritingTests {
    @Test("A written file loads back as the same course")
    func roundTrip() throws {
        let file = try JSONDecoder().decode(CourseFile.self, from: Fixture.data(Fixture.json()))

        let written = try file.jsonData()

        #expect(try JSONDecoder().decode(CourseFile.self, from: written) == file)
        #expect(try CourseLoader.load(written, fileName: Fixture.fileName).get() == Fixture.course())
    }

    @Test("Output is stable: sorted keys, so writing twice gives identical bytes")
    func stableOutput() throws {
        let file = try JSONDecoder().decode(CourseFile.self, from: Fixture.data(Fixture.json()))

        let first = try file.jsonData()
        let text = try #require(String(data: first, encoding: .utf8))

        #expect(try file.jsonData() == first)
        #expect(text.range(of: "\"description\"")!.lowerBound < text.range(of: "\"distanceMeters\"")!.lowerBound)
    }

    @Test("Writing a schema version other than the supported one throws")
    func unsupportedVersion() throws {
        var file = try JSONDecoder().decode(CourseFile.self, from: Fixture.data(Fixture.json()))
        file.schemaVersion = 2

        #expect(throws: UnsupportedSchemaVersionError(schemaVersion: 2)) { try file.jsonData() }
    }
}
