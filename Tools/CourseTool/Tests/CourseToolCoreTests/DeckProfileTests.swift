import Foundation
import Testing

@testable import CourseToolCore

@Suite("Deck profiles")
struct DeckProfileTests {
    private func point(at meters: Double, elevation: Double? = nil, rise: Double? = nil) -> ProfilesFile.Point {
        let c = location(at: meters)
        return ProfilesFile.Point(
            latitude: c.latitude, longitude: c.longitude, elevationMeters: elevation, riseMeters: rise)
    }

    @Test("Control points are placed on the route by position, in order")
    func locate() throws {
        let samples = straightSamples(count: 101)
        let profiles = [
            ProfilesFile.Profile(
                name: "Bridge", source: "test", method: "test",
                points: [point(at: 205, elevation: 10), point(at: 300, elevation: 20), point(at: 395, elevation: 10)])
        ]

        let located = try DeckProfiles.locate(profiles, samples: samples)

        #expect(located.count == 1)
        #expect(zip(located[0], [205.0, 300, 395]).allSatisfy { abs($0 - $1) < 0.01 })
    }

    @Test("A point too far from the route fails")
    func offRoute() {
        let samples = straightSamples(count: 101)
        var far = point(at: 300, elevation: 20)
        far.longitude += 0.001  // about 90 m east
        let profiles = [
            ProfilesFile.Profile(
                name: "Bridge", source: "test", method: "test", points: [point(at: 200, elevation: 10), far])
        ]

        #expect(throws: PipelineError.self) { try DeckProfiles.locate(profiles, samples: samples) }
    }

    @Test("Absolute and rise points resolve to elevations between the profile's ends")
    func resolve() throws {
        let samples = straightSamples(count: 101)
        let raws = samples.map(\.distanceMeters)
        // The ground slopes from 0 m at 0 to 100 m at 1 km.
        let base = raws.map { $0 / 10 }
        let absolute = ProfilesFile.Profile(
            name: "Deck", source: "test", method: "test",
            points: [point(at: 100, elevation: 10), point(at: 200, elevation: 40), point(at: 300, elevation: 30)])
        let modelled = ProfilesFile.Profile(
            name: "Hump", source: "test", method: "test",
            points: [point(at: 600, rise: 0), point(at: 700, rise: 2), point(at: 800, rise: 0)])
        let profiles = [absolute, modelled]

        let (fixed, spans) = try DeckProfiles.resolve(
            profiles, located: try DeckProfiles.locate(profiles, samples: samples), rawDistances: raws, base: base,
            official: { $0 })

        #expect(abs(fixed[15]! - 25) < 1e-6)  // 150 m: halfway between 10 and 40
        #expect(abs(fixed[20]! - 40) < 1e-6)
        #expect(abs(fixed[70]! - 72) < 1e-6)  // 700 m: base line 70 m + 2 m rise
        #expect(abs(fixed[65]! - 66) < 1e-6)  // 650 m: base 65 m + 1 m
        #expect(fixed[35] == nil)
        #expect(spans.map(\.name) == ["Deck", "Hump"])
        #expect(spans[1].controlPoints.map(\.elevationMeters) == [60, 72, 80])
    }

    @Test("A point needs exactly one of elevationMeters and riseMeters")
    func ambiguousPoint() {
        let profiles = [
            ProfilesFile.Profile(
                name: "Bad", source: "test", method: "test",
                points: [point(at: 100, elevation: 10, rise: 2), point(at: 200, elevation: 10)])
        ]

        #expect(throws: PipelineError.self) {
            try DeckProfiles.locate(profiles, samples: straightSamples(count: 101))
        }
    }

    @Test("Profiles take precedence over OSM bridge interpolation, and anchor it at their ends")
    func precedence() throws {
        // Ground at 10 m; a tagged bridge from 300 to 700 m reads 0 m (water). The profile covers 400–600 m.
        let samples = straightSamples(count: 101) { d in d >= 300 && d <= 700 ? 0 : 10 }
        let raws = samples.map(\.distanceMeters)
        let bridge = StructuresFile.Span(
            kind: "bridge", osmWayId: 1, name: "Bridge", highway: "primary", startMeters: 300, endMeters: 700)
        let reasons = ElevationCleaning.suspectReasons(
            samples: samples, distances: raws, trustedSources: ["trusted"], structures: [bridge], manualSpans: [])
        let first = try ElevationCleaning.clean(
            samples: samples, distances: raws, reasons: reasons, steepStepPercent: 100)
        let profiles = [
            ProfilesFile.Profile(
                name: "Deck", source: "test", method: "test",
                points: [point(at: 400, elevation: 14), point(at: 500, elevation: 20), point(at: 600, elevation: 14)])
        ]
        let (fixed, _) = try DeckProfiles.resolve(
            profiles, located: try DeckProfiles.locate(profiles, samples: samples), rawDistances: raws,
            base: first.cleaned, official: { $0 })

        let cleaned = try ElevationCleaning.clean(
            samples: samples, distances: raws, reasons: reasons, fixed: fixed, steepStepPercent: 100)

        #expect(first.cleaned[50] == 10)  // without the profile: flat across the bridge
        #expect(cleaned.cleaned[50] == 20)  // the deck's crest
        // 350 m: on the line from the ground (10 m at 290 m) to the deck's end (14 m at 400 m).
        #expect(abs(cleaned.cleaned[35] - (10 + 4 * 60.0 / 110)) < 1e-6)
        #expect(cleaned.spans.count == 2)  // the bridge either side of the profile
    }
}
