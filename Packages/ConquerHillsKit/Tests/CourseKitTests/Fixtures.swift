import Foundation
import Testing

@testable import CourseKit

/// Builds course files as JSON objects for tests. The defaults describe a valid 2,400 m course.
enum Fixture {
    static let fileName = "fixture.course.json"

    /// The synthetic test course's incline changes, as (atMeters, inclinePercent).
    static let testHillsChanges: [(Double, Double)] = [
        (0, 1), (200, 3), (400, 6.5), (600, 2), (700, -1), (900, -3), (1100, 0.5), (1300, 16), (1500, 4.5),
        (1700, 0), (2000, 2.5),
    ]

    static func json(
        distance: Double = 2400,
        changes: [(Double, Double)] = [(0, 1), (1000, -2), (2000, 3)],
        segments: [[String: Any]] = [],
        spacing: Double = 100
    ) -> [String: Any] {
        let sampleCount = Int((distance / spacing).rounded(.up)) + 1
        return [
            "schemaVersion": 1,
            "id": "fixture",
            "name": "Fixture Course",
            "edition": "2026",
            "location": "Testville",
            "distanceMeters": distance,
            "developmentOnly": false,
            "description": "A course for tests.",
            "source": [
                "route": ["name": "Route source", "url": "https://example.com/route", "license": "Test license"],
                "elevation": [
                    "name": "Elevation source", "url": NSNull(), "license": "Test license", "kind": "modeled",
                ],
                "attribution": "© Test",
                "verified": false,
                "notes": NSNull(),
            ] as [String: Any],
            "processing": ["tool": "fixture", "generatedOn": "2026-10-06", "parameters": ["window": "200"]],
            "stats": [
                "elevationGainMeters": 10.0, "elevationLossMeters": 5.0, "minimumElevationMeters": 1.0,
                "maximumElevationMeters": 12.0,
            ],
            "elevationProfile": [
                "sampleSpacingMeters": spacing,
                "elevationsMeters": Array(repeating: 5.0, count: sampleCount),
            ] as [String: Any],
            "inclineChanges": changes.map { ["atMeters": $0.0, "inclinePercent": $0.1] },
            "segments": segments,
        ]
    }

    static func segment(id: String = "hill", name: String = "The hill", start: Double, end: Double) -> [String: Any] {
        ["id": id, "name": name, "startMeters": start, "endMeters": end]
    }

    static func data(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func load(_ object: [String: Any], fileName: String = fileName) throws -> Result<
        Course, CourseValidationFailure
    > {
        CourseLoader.load(try data(object), fileName: fileName)
    }

    /// Loads a course that is expected to be valid.
    static func course(_ object: [String: Any] = json()) throws -> Course {
        try load(object).get()
    }

    /// The problems reported for a course that is expected to be invalid.
    static func problems(
        _ object: [String: Any], fileName: String = fileName, sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> [CourseProblem] {
        switch try load(object, fileName: fileName) {
        case .success:
            Issue.record("Expected the course to be rejected", sourceLocation: sourceLocation)
            return []
        case .failure(let failure):
            #expect(failure.fileName == fileName, sourceLocation: sourceLocation)
            return failure.problems
        }
    }

    /// A course using the synthetic test course's incline changes.
    static func testHills() throws -> Course {
        try course(json(changes: testHillsChanges))
    }
}

extension Dictionary where Key == String, Value == Any {
    /// Returns a copy with the value at a dotted key path (e.g. `source.route.name`) replaced, or removed if
    /// `value` is nil.
    func setting(_ path: String, to value: Any?) -> [String: Any] {
        var components = path.split(separator: ".").map(String.init)
        let key = components.removeFirst()
        var copy = self
        if components.isEmpty {
            copy[key] = value
        } else {
            let child = (self[key] as? [String: Any]) ?? [:]
            copy[key] = child.setting(components.joined(separator: "."), to: value)
        }
        return copy
    }
}
