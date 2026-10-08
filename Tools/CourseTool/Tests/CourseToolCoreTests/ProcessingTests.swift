import Foundation
import Testing

@testable import CourseToolCore

@Suite("Elevation cleaning")
struct CleaningTests {
    let structureSettings = CourseConfig.StructureSettings(
        bufferMeters: 12, maximumAngleDegrees: 30, ignoredHighways: ["motorway"])

    func clean(_ samples: [ElevationSamplesFile.Sample], reasons: [SuspectReason?]) throws -> CleanedElevation {
        try ElevationCleaning.clean(
            samples: samples, distances: samples.map(\.distanceMeters), reasons: reasons, steepStepPercent: 15)
    }

    @Test("A suspect run is replaced by a straight line between trusted neighbours")
    func interpolatesRun() throws {
        var samples = straightSamples(count: 11) { $0 / 10 }  // 1% grade
        samples[4].elevationMeters = 0  // a false dip on a bridge
        samples[5].elevationMeters = 0
        var reasons = [SuspectReason?](repeating: nil, count: 11)
        reasons[4] = .noData
        reasons[5] = .noData

        let cleaned = try clean(samples, reasons: reasons)

        #expect(abs(cleaned.cleaned[4] - 4) < 1e-9)
        #expect(abs(cleaned.cleaned[5] - 5) < 1e-9)
        #expect(cleaned.spans == [InterpolatedSpan(startMeters: 40, endMeters: 50, reasons: ["no data"])])
    }

    @Test("Suspect runs at the start or end take the nearest trusted value")
    func runsAtEnds() throws {
        let samples = straightSamples(count: 6) { $0 }
        let reasons: [SuspectReason?] = [.noData, nil, nil, nil, nil, .noData]

        let cleaned = try clean(samples, reasons: reasons)

        #expect(cleaned.cleaned.first == 10)
        #expect(cleaned.cleaned.last == 40)
    }

    @Test("Untrusted sources and no-data samples are flagged; manual spans interpolate or keep")
    func reasons() {
        var samples = straightSamples(count: 10)
        samples[1].source = "10m"
        samples[2].elevationMeters = nil
        samples[6].source = "10m"
        let spans = [
            CourseConfig.ManualSpan(startMeters: 40, endMeters: 50, action: .interpolate, reason: "false dip"),
            CourseConfig.ManualSpan(startMeters: 60, endMeters: 60, action: .keep, reason: "real rise"),
        ]

        let reasons = ElevationCleaning.suspectReasons(
            samples: samples, distances: samples.map(\.distanceMeters), trustedSources: ["trusted"], structures: [],
            settings: structureSettings, manualSpans: spans)

        #expect(reasons[0] == nil)
        #expect(reasons[1] == .untrustedSource("10m"))
        #expect(reasons[2] == .noData)
        #expect(reasons[4] == .manual("false dip"))
        #expect(reasons[5] == .manual("false dip"))
        #expect(reasons[6] == nil)  // kept despite the untrusted source
    }

    @Test("A bridge carrying the route is flagged; one crossing over it is not")
    func structures() {
        let samples = straightSamples(count: 30)  // runs north
        let along = StructuresFile.Way(
            id: 1, tags: ["bridge": "yes", "highway": "primary"],
            geometry: [location(at: 100), location(at: 150)])
        let east = Coordinate(latitude: location(at: 250).latitude, longitude: 139.001)
        let west = Coordinate(latitude: location(at: 250).latitude, longitude: 138.999)
        let across = StructuresFile.Way(id: 2, tags: ["bridge": "yes", "highway": "footway"], geometry: [west, east])
        let expressway = StructuresFile.Way(
            id: 3, tags: ["bridge": "yes", "highway": "motorway"], geometry: [location(at: 200), location(at: 240)])

        let reasons = ElevationCleaning.suspectReasons(
            samples: samples, distances: samples.map(\.distanceMeters), trustedSources: ["trusted"],
            structures: [along, across, expressway], settings: structureSettings, manualSpans: [])

        #expect(reasons[12] == .structure(wayID: 1, kind: "bridge", name: nil))
        #expect(reasons[22] == nil)  // under the expressway (ignored highway)
        #expect(reasons[25] == nil)  // under the footbridge (crossing, not along)
    }

    @Test("Steep steps that remain after cleaning are listed")
    func steepSteps() throws {
        var samples = straightSamples(count: 5)
        samples[3].elevationMeters = 12  // +20% over 10 m, then −20%

        let cleaned = try clean(samples, reasons: [SuspectReason?](repeating: nil, count: 5))

        #expect(cleaned.steepSteps.map(\.atMeters) == [20, 30])
    }
}

@Suite("Smoothing and incline intervals")
struct IntervalTests {
    func series(length: Double, step: Double = 10, _ elevation: (Double) -> Double) -> ElevationSeries {
        let distances = Array(stride(from: 0, through: length, by: step))
        return ElevationSeries(distances: distances, elevations: distances.map(elevation))
    }

    @Test("Smoothing preserves a constant grade, including at the ends")
    func smoothingConstantGrade() {
        let s = series(length: 2000) { 5 + $0 * 0.02 }

        let smoothed = s.smoothed(windowMeters: 200)

        #expect(zip(smoothed.elevations, s.elevations).allSatisfy { abs($0 - $1) < 1e-9 })
    }

    @Test("Smoothing spreads a single spike")
    func smoothingSpike() {
        let s = series(length: 1000) { $0 == 500 ? 10 : 0 }

        let smoothed = s.smoothed(windowMeters: 200)

        #expect(smoothed.elevation(at: 500) < 1)
        #expect(smoothed.elevation(at: 450) > 0)
    }

    @Test("A constant-grade hill gives one interval")
    func constantGrade() {
        let intervals = InclineIntervals.build(
            series: series(length: 3000) { $0 * 0.02 }, totalMeters: 3000, blockMeters: 100, minimumMeters: 400,
            step: 0.5)

        #expect(intervals == [InclineInterval(startMeters: 0, endMeters: 3000, inclinePercent: 2)])
    }

    @Test("Noise under a quarter percent rounds to flat")
    func smallNoise() {
        let intervals = InclineIntervals.build(
            series: series(length: 2000) { sin($0 / 50) * 0.1 }, totalMeters: 2000, blockMeters: 100,
            minimumMeters: 400, step: 0.5)

        #expect(intervals == [InclineInterval(startMeters: 0, endMeters: 2000, inclinePercent: 0)])
    }

    @Test("Short intervals merge until every interval meets the minimum, with no equal neighbours")
    func minimumLength() {
        // Flat, a 200 m bump of +3%, flat, a 1 km climb of +2%, flat.
        let s = series(length: 4000) { d in
            switch d {
            case ..<1000: 0
            case ..<1200: (d - 1000) * 0.03
            case ..<2000: 6
            case ..<3000: 6 + (d - 2000) * 0.02
            default: 26
            }
        }

        let intervals = InclineIntervals.build(
            series: s, totalMeters: 4000, blockMeters: 100, minimumMeters: 400, step: 0.5)

        #expect(intervals.allSatisfy { $0.length >= 400 })
        #expect(zip(intervals, intervals.dropFirst()).allSatisfy { $0.inclinePercent != $1.inclinePercent })
        #expect(intervals.first?.startMeters == 0)
        #expect(intervals.last?.endMeters == 4000)
        #expect(intervals.contains { $0.inclinePercent == 2 && $0.length >= 1000 })
    }

    @Test("Merging preserves net elevation: the merged incline is the span's net rise over its length")
    func mergePreservesNetRise() {
        // 300 m at +4% next to 300 m at 0%: too short apart, together +2% over 600 m.
        let s = series(length: 600) { d in d < 300 ? d * 0.04 : 12 }

        let intervals = InclineIntervals.build(
            series: s, totalMeters: 600, blockMeters: 100, minimumMeters: 400, step: 0.5)

        #expect(intervals == [InclineInterval(startMeters: 0, endMeters: 600, inclinePercent: 2)])
    }

    @Test("Total gain minus loss equals finish minus start")
    func gainLossBalance() {
        let s = series(length: 5000) { sin($0 / 300) * 8 + $0 * 0.001 }

        let (gain, loss) = s.gainAndLoss

        #expect(abs((gain - loss) - (s.elevations.last! - s.elevations.first!)) < 1e-9)
    }
}
