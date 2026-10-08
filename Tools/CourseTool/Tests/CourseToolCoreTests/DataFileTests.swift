import Foundation
import Testing

@testable import CourseToolCore

@Suite("Compact data files")
struct DataFileTests {
    @Test("Polyline encoding matches Google's published example (precision 5)")
    func polylineKnownVector() {
        let line = [
            Coordinate(latitude: 38.5, longitude: -120.2), Coordinate(latitude: 40.7, longitude: -120.95),
            Coordinate(latitude: 43.252, longitude: -126.453),
        ]

        #expect(Polyline.encode(line, precision: 1e5) == "_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        #expect(Polyline.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@", precision: 1e5) == line)
    }

    @Test("Precision-6 polylines round coordinates once; decoding and re-encoding is stable")
    func polylineRoundTrip() {
        let line = [
            Coordinate(latitude: 35.689_812_34, longitude: 139.693_501_87),
            Coordinate(latitude: 35.681_401_49, longitude: 139.764_600_51),
        ]

        let decoded = Polyline.decode(Polyline.encode(line))

        #expect(
            decoded == [
                Coordinate(latitude: 35.689812, longitude: 139.693502),
                Coordinate(latitude: 35.681401, longitude: 139.764601),
            ])
        #expect(Polyline.decode(Polyline.encode(decoded)) == decoded)
        #expect(RouteFile(line: line, properties: [:]).line == decoded)
    }

    @Test("Elevation samples store a value and a one-character source code each, and resume from what's missing")
    func elevationSamplesFile() throws {
        var file = ElevationSamplesFile(
            provider: "gsi", routeFingerprint: "f", routeSmoothingMeters: 40, sampleSpacingMeters: 10, count: 4)
        #expect(file.missing == [0, 1, 2, 3])

        file.record(41.0, source: "1m laser", at: 0)
        file.record(40.5, source: "1m laser", at: 2)
        file.record(nil, source: "no data", at: 1)

        #expect(file.missing == [3])
        #expect(!file.isComplete)
        #expect(file.sourceCodes == "aba?")
        #expect(file.sources == ["a": "1m laser", "b": "no data"])
        #expect(file.sourceLabels == ["1m laser", "no data", "1m laser", nil])

        file.record(39.9, source: "1m laser", at: 3)
        let positions = (0..<4).map {
            RouteSampling.Position(distanceMeters: Double($0) * 10, location: location(at: Double($0) * 10))
        }
        let samples = try file.samples(at: positions)
        #expect(file.isComplete)
        #expect(samples.map(\.elevationMeters) == [41.0, nil, 40.5, 39.9])
        #expect(throws: PipelineError.self) { try file.samples(at: Array(positions.prefix(3))) }
    }

    @Test("Machine-written files are compact JSON on one line")
    func compactJSON() throws {
        let file = ElevationSamplesFile(
            provider: "gsi", routeFingerprint: "f", routeSmoothingMeters: 40, sampleSpacingMeters: 10, count: 2)

        let text = try #require(String(data: try PipelineJSON.encode(file), encoding: .utf8))

        #expect(text.filter { $0 == "\n" }.count == 1)
        #expect(text.hasSuffix("}\n"))
    }

    @Test("Sample positions are recomputed identically from the stored route")
    func positionsAreDeterministic() {
        let route = RouteFile(line: [location(at: 0), location(at: 1234)], properties: [:]).line

        let a = RouteSampling.positions(route: route, smoothingMeters: 40, spacing: 10)
        let b = RouteSampling.positions(route: route, smoothingMeters: 40, spacing: 10)

        #expect(a == b)
        #expect(a.count == 125)
    }
}
