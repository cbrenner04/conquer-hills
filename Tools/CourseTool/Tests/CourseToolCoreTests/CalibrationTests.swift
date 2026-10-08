import Testing

@testable import CourseToolCore

/// Samples every 10 m along a line of longitude, so distance and position are easy to relate.
func straightSamples(count: Int, elevation: (Double) -> Double = { _ in 10 }) -> [ElevationSamplesFile.Sample] {
    (0..<count).map { i in
        let d = Double(i) * 10
        return ElevationSamplesFile.Sample(
            distanceMeters: d, location: location(at: d), elevationMeters: elevation(d), source: "trusted")
    }
}

/// The point `meters` north of (35, 139).
func location(at meters: Double) -> Coordinate {
    Coordinate(latitude: 35 + meters / (Geo.earthRadiusMeters * .pi / 180), longitude: 139)
}

func checkpoint(_ name: String, official: Double, at raw: Double, anchor: Bool) -> CourseConfig.Checkpoint {
    CourseConfig.Checkpoint(name: name, officialMeters: official, location: location(at: raw), anchor: anchor)
}

@Suite("Distance calibration")
struct CalibrationTests {
    @Test("Checkpoints are found in order, including a place passed twice")
    func locateInOrder() throws {
        // An out-and-back: 0 → 1000 m → back to 0, as samples with increasing distance.
        let samples = (0...200).map { i -> ElevationSamplesFile.Sample in
            let along = Double(i) * 10
            let position = along <= 1000 ? along : 2000 - along
            return .init(distanceMeters: along, location: location(at: position), elevationMeters: 0, source: "t")
        }
        let checkpoints = [
            checkpoint("Bridge out", official: 500, at: 500, anchor: false),
            checkpoint("Turnaround", official: 1000, at: 1000, anchor: true),
            checkpoint("Bridge back", official: 1500, at: 500, anchor: false),
        ]

        let located = try Checkpoints.locate(checkpoints, samples: samples, radiusMeters: 50)

        #expect(located.map(\.rawMeters) == [500, 1000, 1500])
    }

    @Test("A checkpoint far from the route is an error")
    func checkpointOffRoute() {
        let far = CourseConfig.Checkpoint(
            name: "Elsewhere", officialMeters: 100, location: Coordinate(latitude: 36, longitude: 139), anchor: false)

        #expect(throws: PipelineError.self) {
            try Checkpoints.locate([far], samples: straightSamples(count: 20), radiusMeters: 100)
        }
    }

    @Test("Piecewise scaling lands anchors exactly and the total on the official distance")
    func piecewise() throws {
        let located = [
            LocatedCheckpoint(
                checkpoint: checkpoint("A", official: 1000, at: 1100, anchor: true), sampleIndex: 110,
                rawMeters: 1100, offRouteMeters: 0)
        ]

        let calibration = try Calibration(located: located, rawTotal: 2000, officialTotal: 2100)

        #expect(calibration.official(forRaw: 0) == 0)
        #expect(abs(calibration.official(forRaw: 1100) - 1000) < 1e-9)
        #expect(abs(calibration.official(forRaw: 550) - 500) < 1e-9)
        #expect(abs(calibration.official(forRaw: 2000) - 2100) < 1e-9)
        #expect(abs(calibration.official(forRaw: 1550) - 1550) < 1e-9)
    }

    @Test("A finish anchor ends the course; the trace beyond it is dropped")
    func finishAnchor() throws {
        let located = [
            LocatedCheckpoint(
                checkpoint: checkpoint("Finish", official: 2000, at: 1950, anchor: true), sampleIndex: 195,
                rawMeters: 1950, offRouteMeters: 0)
        ]

        let calibration = try Calibration(located: located, rawTotal: 2010, officialTotal: 2000)

        #expect(calibration.rawEnd == 1950)
        #expect(abs(calibration.official(forRaw: 1950) - 2000) < 1e-9)
    }

    @Test("Anchors out of order are rejected")
    func anchorsOutOfOrder() {
        #expect(throws: PipelineError.self) {
            try Calibration(anchors: [(0, 0), (500, 1000), (400, 1500), (900, 2000)])
        }
    }

    @Test("Section errors compare each traced stretch with its official length")
    func sections() {
        let located = [
            LocatedCheckpoint(
                checkpoint: checkpoint("A", official: 1000, at: 0, anchor: false), sampleIndex: 0, rawMeters: 1350,
                offRouteMeters: 0),
            LocatedCheckpoint(
                checkpoint: checkpoint("B", official: 2000, at: 0, anchor: false), sampleIndex: 0, rawMeters: 2400,
                offRouteMeters: 0),
        ]

        let sections = Checkpoints.sections(located, rawEnd: 3000, officialTotal: 3000)

        #expect(sections.map(\.errorMeters) == [350, 50, -400])
        #expect(sections.map(\.toName) == ["A", "B", "Finish"])
    }
}
