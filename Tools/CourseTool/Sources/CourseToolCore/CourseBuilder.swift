import CourseKit
import Foundation

/// Everything `build` reads, all committed in `CourseData/<id>/`. No network access.
public struct BuildInputs: Sendable {
    public var config: CourseConfig
    public var samples: ElevationSamplesFile
    public var structures: StructuresFile
    public var route: [Coordinate]
    public var waypoints: [NamedPoint]

    public init(
        config: CourseConfig, samples: ElevationSamplesFile, structures: StructuresFile, route: [Coordinate],
        waypoints: [NamedPoint]
    ) {
        self.config = config
        self.samples = samples
        self.structures = structures
        self.route = route
        self.waypoints = waypoints
    }

    public static func load(from files: CourseDataFiles, config: CourseConfig) throws -> BuildInputs {
        let waypoints =
            FileManager.default.fileExists(atPath: files.waypoints.path)
            ? try GeoJSON.readWaypoints(Data(contentsOf: files.waypoints)) : []
        return BuildInputs(
            config: config,
            samples: try PipelineJSON.decode(ElevationSamplesFile.self, from: files.elevationSamples),
            structures: try PipelineJSON.decode(StructuresFile.self, from: files.structures),
            route: try GeoJSON.readRoute(Data(contentsOf: files.route)).line,
            waypoints: waypoints)
    }
}

public struct AcceptanceResult: Equatable, Sendable {
    public var name: String
    public var passed: Bool
    public var detail: String
}

public struct BuildResult: Sendable {
    public var courseFile: CourseFile
    public var courseData: Data
    public var course: Course
    public var located: [LocatedCheckpoint]
    public var sections: [CalibrationSection]
    public var calibration: Calibration
    public var cleaned: CleanedElevation
    public var smoothed: ElevationSeries
    public var intervals: [InclineInterval]
    public var acceptance: [AcceptanceResult]
    public var maximumSectionErrorMeters: Double

    public var failingSections: [CalibrationSection] {
        sections.filter { abs($0.errorMeters) > maximumSectionErrorMeters }
    }

    public var allChecksPass: Bool { failingSections.isEmpty && acceptance.allSatisfy(\.passed) }

    public var summaryLines: [String] {
        var lines = ["\(course.id): \(intervals.count) incline intervals, \(cleaned.spans.count) interpolated spans"]
        for section in sections {
            let flag = abs(section.errorMeters) > maximumSectionErrorMeters ? "  ✗ FAIL" : ""
            lines.append(
                String(
                    format: "  %@ → %@: traced %.0f m vs official %.0f m (%+.0f)%@", section.fromName, section.toName,
                    section.rawMeters, section.officialMeters, section.errorMeters, flag))
        }
        for check in acceptance {
            lines.append("  \(check.passed ? "✓" : "✗ FAIL") \(check.name): \(check.detail)")
        }
        return lines
    }
}

public enum CourseBuilder {
    public static let toolVersion = "course-tool 0.1.0"

    public static func build(_ inputs: BuildInputs) throws -> BuildResult {
        let config = inputs.config
        let settings = config.processing
        guard inputs.samples.isComplete else {
            throw PipelineError("elevation samples are incomplete: run `make course-elevation ID=\(config.id)`")
        }
        let expected = RouteSampling.fingerprint(
            route: inputs.route, smoothingMeters: settings.routeSmoothingMeters, spacing: settings.sampleSpacingMeters)
        guard inputs.samples.routeFingerprint == expected else {
            throw PipelineError("elevation samples don't match the current route: rerun `make course-elevation`")
        }

        // 1. Calibrate distance to the official checkpoints, and drop anything traced past the finish.
        let allSamples = inputs.samples.samples
        let located = try Checkpoints.locate(
            config.checkpoints, samples: allSamples, radiusMeters: settings.checkpointSearchRadiusMeters)
        let calibration = try Calibration(
            located: located, rawTotal: allSamples.last!.distanceMeters, officialTotal: config.officialDistanceMeters)
        let sections = Checkpoints.sections(
            located, rawEnd: calibration.rawEnd, officialTotal: config.officialDistanceMeters)
        let samples = allSamples.filter { $0.distanceMeters <= calibration.rawEnd + 1e-6 }
        let distances = samples.map { roundTo(calibration.official(forRaw: $0.distanceMeters), places: 3) }

        // 2. Clean: interpolate bridges, tunnels, untrusted sources and manual spans.
        let reasons = ElevationCleaning.suspectReasons(
            samples: samples, distances: distances, trustedSources: config.elevation.trustedSources,
            structures: inputs.structures.ways, settings: config.structures, manualSpans: config.manualSpans)
        let cleaned = try ElevationCleaning.clean(
            samples: samples, distances: distances, reasons: reasons, steepStepPercent: settings.steepStepPercent)

        // 3. Smooth, then 4. turn grade into incline intervals.
        let smoothed = ElevationSeries(distances: distances, elevations: cleaned.cleaned)
            .smoothed(windowMeters: settings.smoothingWindowMeters)
        let total = config.officialDistanceMeters
        let intervals = InclineIntervals.build(
            series: smoothed, totalMeters: total, blockMeters: settings.gradeBlockMeters,
            minimumMeters: settings.minimumIntervalMeters, step: settings.inclineStepPercent)

        // 5. Stats and chart samples, from the smoothed series.
        let (gain, loss) = smoothed.gainAndLoss
        let profileDistances =
            Array(stride(from: 0, to: total, by: settings.profileSampleSpacingMeters)) + [total]

        let file = CourseFile(
            id: config.id, name: config.name, edition: config.edition, location: config.location,
            distanceMeters: total, developmentOnly: false, description: config.description, source: config.source,
            processing: CourseFile.Processing(
                tool: toolVersion, generatedOn: inputs.samples.fetchedOn ?? "unknown",
                parameters: parameters(config: config, calibration: calibration, inputs: inputs)),
            stats: CourseFile.Stats(
                elevationGainMeters: roundTo(gain, places: 1), elevationLossMeters: roundTo(loss, places: 1),
                minimumElevationMeters: roundTo(smoothed.elevations.min()!, places: 1),
                maximumElevationMeters: roundTo(smoothed.elevations.max()!, places: 1)),
            elevationProfile: CourseFile.ElevationProfile(
                sampleSpacingMeters: settings.profileSampleSpacingMeters,
                elevationsMeters: profileDistances.map { roundTo(smoothed.elevation(at: $0), places: 1) }),
            inclineChanges: intervals.map {
                CourseFile.InclineChange(
                    atMeters: roundTo($0.startMeters, places: 1), inclinePercent: $0.inclinePercent)
            },
            segments: config.segments)

        // 6. Write through CourseKit and load it back: a file the app would reject can't be produced.
        let data = try file.jsonData()
        let course: Course
        switch CourseLoader.load(data, fileName: config.id + CourseLoader.fileSuffix) {
        case .success(let loaded): course = loaded
        case .failure(let failure): throw PipelineError("generated course is invalid: \(failure)")
        }

        let unsmoothed = ElevationSeries(distances: distances, elevations: cleaned.cleaned)
        let acceptance = config.acceptance.map {
            Acceptance.evaluate($0, cleaned: unsmoothed, smoothed: smoothed, intervals: intervals)
        }
        return BuildResult(
            courseFile: file, courseData: data, course: course, located: located, sections: sections,
            calibration: calibration, cleaned: cleaned, smoothed: smoothed, intervals: intervals,
            acceptance: acceptance, maximumSectionErrorMeters: settings.maximumSectionErrorMeters)
    }

    static func parameters(config: CourseConfig, calibration: Calibration, inputs: BuildInputs) -> [String: String] {
        let p = config.processing
        func number(_ value: Double) -> String { String(format: "%g", value) }
        let scales = calibration.sectionScales.map {
            String(format: "%.0f-%.0f:%.4f", $0.fromOfficial, $0.toOfficial, $0.scale)
        }
        return [
            "routeSmoothingMeters": number(p.routeSmoothingMeters),
            "sampleSpacingMeters": number(p.sampleSpacingMeters),
            "smoothingWindowMeters": number(p.smoothingWindowMeters),
            "gradeBlockMeters": number(p.gradeBlockMeters),
            "minimumIntervalMeters": number(p.minimumIntervalMeters),
            "inclineStepPercent": number(p.inclineStepPercent),
            "elevationProvider": inputs.samples.provider,
            "osmStructuresTimestamp": inputs.structures.osmTimestamp,
            "calibrationScales": scales.joined(separator: " "),
        ]
    }
}

public enum Acceptance {
    public static func evaluate(
        _ check: CourseConfig.AcceptanceCheck, cleaned: ElevationSeries, smoothed: ElevationSeries,
        intervals: [InclineInterval]
    ) -> AcceptanceResult {
        let totalsSeries = check.smoothingWindowMeters.map { cleaned.smoothed(windowMeters: $0) } ?? smoothed
        let (gain, loss) = totalsSeries.gainAndLoss
        func range(_ value: Double, unit: String = "m") -> AcceptanceResult {
            let ok = value >= (check.min ?? -.infinity) - 1e-9 && value <= (check.max ?? .infinity) + 1e-9
            let bounds = [check.min.map { String(format: "≥ %g", $0) }, check.max.map { String(format: "≤ %g", $0) }]
                .compactMap { $0 }.joined(separator: ", ")
            return AcceptanceResult(
                name: check.name, passed: ok, detail: String(format: "%.1f %@ (expected %@)", value, unit, bounds))
        }
        let start = totalsSeries.elevations.first!
        let end = totalsSeries.elevations.last!
        switch check.kind {
        case .elevationAt:
            return range(smoothed.elevation(at: check.atMeters ?? 0))
        case .maximumElevation:
            let from = check.fromMeters ?? 0
            let to = check.toMeters ?? .infinity
            let values = zip(smoothed.distances, smoothed.elevations).filter { $0.0 >= from && $0.0 <= to }.map(\.1)
            return range(values.max() ?? .nan)
        case .drop:
            return range(smoothed.elevation(at: check.fromMeters ?? 0) - smoothed.elevation(at: check.toMeters ?? 0))
        case .gain:
            return range(gain)
        case .loss:
            return range(loss)
        case .netBalance:
            return range(abs((gain - loss) - (end - start)))
        case .maximumIncline:
            return range(intervals.map { abs($0.inclinePercent) }.max() ?? 0, unit: "%")
        case .noDip:
            let at = check.atMeters ?? 0
            let radius = check.radiusMeters ?? 300
            let edges = min(smoothed.elevation(at: at - radius), smoothed.elevation(at: at + radius))
            let lowest =
                zip(smoothed.distances, smoothed.elevations)
                .filter { abs($0.0 - at) <= radius }.map(\.1).min() ?? edges
            let dip = edges - lowest
            return AcceptanceResult(
                name: check.name, passed: dip <= 0.5,
                detail: String(format: "lowest point %.1f m below the lower edge (allowed 0.5 m)", max(0, dip)))
        }
    }
}
