import CourseKit
import Foundation
import Testing

@testable import CourseToolCore

@Suite("End-to-end build")
struct EndToEndTests {
    /// A 5 km course running north: flat for 2 km, a 1 km climb at 3%, then flat. A "bridge" at 4.0–4.1 km
    /// reports river level, which cleaning must remove.
    func inputs() -> BuildInputs {
        let route = [location(at: 0), location(at: 5000)]
        var samples = RouteSampling.prepare(
            existing: nil, route: route, provider: "test", smoothingMeters: 40, spacing: 10)
        let positions = RouteSampling.positions(route: route, smoothingMeters: 40, spacing: 10)
        for (i, position) in positions.enumerated() {
            let d = position.distanceMeters
            let onBridge = d >= 4000 && d <= 4100
            let elevation = onBridge ? 1 : (d < 2000 ? 10 : d < 3000 ? 10 + (d - 2000) * 0.03 : 40)
            samples.record(elevation, source: onBridge ? "fallback" : "trusted", at: i)
        }
        samples.fetchedOn = "2026-10-07"
        let config = CourseConfig(
            id: "test-course", name: "Test Course", edition: "2026", location: "Testville", description: nil,
            officialDistanceMeters: 5000,
            source: CourseFile.Source(
                route: .init(name: "Test", url: nil, license: "Test"),
                elevation: .init(name: "Test", url: nil, license: "Test", kind: .modeled), attribution: "© Test",
                verified: false, notes: nil),
            route: .waypoints(routerBaseURL: "https://example.invalid"),
            elevation: .init(provider: "test", trustedSources: ["trusted"]),
            structures: .init(
                bufferMeters: 12, maximumAngleDegrees: 30, ignoredHighways: [], ignoredTunnelHighways: []),
            processing: .init(
                routeSmoothingMeters: 40, sampleSpacingMeters: 10, smoothingWindowMeters: 200, gradeBlockMeters: 100,
                minimumIntervalMeters: 400, inclineStepPercent: 0.5, profileSampleSpacingMeters: 100,
                maximumSectionErrorMeters: 300, steepStepPercent: 15, checkpointSearchRadiusMeters: 100),
            checkpoints: [
                checkpoint("Halfway", official: 2500, at: 2500, anchor: true),
                checkpoint("Finish", official: 5000, at: 5000, anchor: true),
            ],
            manualSpans: [],
            segments: [.init(id: "the-climb", name: "The climb", startMeters: 2000, endMeters: 3000)],
            acceptance: [
                .init(name: "Climb", kind: .drop, fromMeters: 3500, toMeters: 1500, min: 25, max: 35),
                .init(name: "No bridge dip", kind: .noDip, atMeters: 4050, radiusMeters: 200),
                .init(name: "Gentle", kind: .maximumIncline, max: 3),
            ])
        let structures = StructuresFile(
            osmTimestamp: "2026-10-07T00:00:00Z", settings: config.structures,
            routeFingerprint: RouteSampling.fingerprint(route: route, smoothingMeters: 40, spacing: 10), spans: [])
        return BuildInputs(config: config, samples: samples, structures: structures, route: route, waypoints: [])
    }

    @Test("A synthetic course builds into a file the app accepts, and every check passes")
    func builds() throws {
        let result = try CourseBuilder.build(inputs())

        #expect(result.allChecksPass, "\(result.summaryLines.joined(separator: "\n"))")
        let course = try CourseLoader.load(result.courseData, fileName: "test-course.course.json").get()
        #expect(course.distanceMeters == 5000)
        #expect(course.inclineIntervals.contains { $0.inclinePercent == 3 })
        #expect(course.curatedSegments.map(\.id) == ["the-climb"])
        #expect(result.cleaned.spans.count == 1)
        #expect(result.courseFile.processing.generatedOn == "2026-10-07")
    }

    @Test("Building twice produces byte-identical output")
    func deterministic() throws {
        let first = try CourseBuilder.build(inputs()).courseData
        let second = try CourseBuilder.build(inputs()).courseData

        #expect(first == second)
    }

    @Test("Samples that don't match the route are rejected")
    func staleSamples() {
        var stale = inputs()
        stale.route = [location(at: 0), location(at: 5100)]

        #expect(throws: PipelineError.self) { try CourseBuilder.build(stale) }
    }

    @Test("Gain and loss checks can be measured at their own smoothing window")
    func checkSmoothingWindow() throws {
        var inputs = inputs()
        // Add 1 m ripples with a 400 m wavelength: build smoothing (200 m) keeps some, 1 km smoothing removes them.
        let positions = RouteSampling.positions(route: inputs.route, smoothingMeters: 40, spacing: 10)
        for (i, position) in positions.enumerated() {
            inputs.samples.elevations[i]! += sin(position.distanceMeters / 400 * 2 * .pi)
        }
        inputs.config.acceptance = [
            .init(name: "Gain, build smoothing", kind: .gain, min: 0, max: 1000),
            .init(name: "Gain, 1 km smoothing", kind: .gain, min: 0, max: 1000, smoothingWindowMeters: 1000),
        ]

        let result = try CourseBuilder.build(inputs)

        let gains = result.acceptance.map { Double($0.detail.split(separator: " ")[0])! }
        #expect(gains[0] > 25)
        #expect(gains[1] < gains[0])
        #expect(abs(gains[0] - result.courseFile.stats.elevationGainMeters) < 0.1)
    }

    @Test("Structure spans computed for a different route or settings are rejected")
    func staleStructures() {
        var inputs = inputs()
        inputs.structures.settings.bufferMeters = 20

        #expect(throws: PipelineError.self) { try CourseBuilder.build(inputs) }
    }

    @Test("The review report renders")
    func report() throws {
        let inputs = inputs()
        let html = ReviewReport.html(for: try CourseBuilder.build(inputs), inputs: inputs)

        #expect(html.contains("<svg"))
        #expect(html.contains("Test Course"))
    }
}
