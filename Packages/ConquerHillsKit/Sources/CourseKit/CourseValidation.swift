/// A reason a course file was rejected.
public enum CourseProblem: Equatable, Sendable, CustomStringConvertible {
    /// Not valid JSON, or a value of the wrong type.
    case unreadable(String)
    case unsupportedSchemaVersion(Int)
    case unknownField(path: String)
    case missingField(path: String)
    case invalidID(String)
    case idDoesNotMatchFileName(id: String, fileName: String)
    case emptyName
    case invalidDistance(Double)
    case noInclineChanges
    case firstInclineChangeNotAtStart(atMeters: Double)
    case inclineChangeNotAfterPrevious(index: Int)
    case inclineChangeNotBeforeFinish(index: Int)
    case inclineOutOfRange(index: Int, inclinePercent: Double)
    case inclineNotHalfPercent(index: Int, inclinePercent: Double)
    case inclineRepeatsPrevious(index: Int)
    case invalidSampleSpacing(Double)
    case elevationSampleCountMismatch(expected: Int, actual: Int)
    case elevationNotFinite(index: Int)
    case invalidStats(String)
    case emptySegmentID(index: Int)
    case duplicateSegmentID(String)
    case emptySegmentName(index: Int)
    case segmentOutOfRange(index: Int)

    public var description: String {
        switch self {
        case .unreadable(let detail): "unreadable: \(detail)"
        case .unsupportedSchemaVersion(let version): "unsupported schemaVersion \(version)"
        case .unknownField(let path): "unknown field \(path)"
        case .missingField(let path): "missing field \(path)"
        case .invalidID(let id): "id \"\(id)\" is not a lowercase slug"
        case .idDoesNotMatchFileName(let id, let fileName): "id \"\(id)\" does not match file name \(fileName)"
        case .emptyName: "name is empty"
        case .invalidDistance(let distance): "distanceMeters \(distance) must be finite and positive"
        case .noInclineChanges: "inclineChanges is empty"
        case .firstInclineChangeNotAtStart(let at): "first incline change is at \(at) m, not 0"
        case .inclineChangeNotAfterPrevious(let index): "inclineChanges[\(index)] is not after the previous change"
        case .inclineChangeNotBeforeFinish(let index): "inclineChanges[\(index)] is not before the finish"
        case .inclineOutOfRange(let index, let incline): "inclineChanges[\(index)] incline \(incline)% is beyond ±30%"
        case .inclineNotHalfPercent(let index, let incline):
            "inclineChanges[\(index)] incline \(incline)% is not a multiple of 0.5"
        case .inclineRepeatsPrevious(let index): "inclineChanges[\(index)] repeats the previous incline"
        case .invalidSampleSpacing(let spacing): "sampleSpacingMeters \(spacing) must be finite and positive"
        case .elevationSampleCountMismatch(let expected, let actual):
            "expected \(expected) elevation samples, found \(actual)"
        case .elevationNotFinite(let index): "elevationsMeters[\(index)] is not finite"
        case .invalidStats(let detail): "stats: \(detail)"
        case .emptySegmentID(let index): "segments[\(index)] has an empty id"
        case .duplicateSegmentID(let id): "segment id \"\(id)\" is used more than once"
        case .emptySegmentName(let index): "segments[\(index)] has an empty name"
        case .segmentOutOfRange(let index): "segments[\(index)] must satisfy 0 ≤ start < end ≤ distance"
        }
    }
}

/// Every problem found in one course file.
public struct CourseValidationFailure: Error, Equatable, Sendable, CustomStringConvertible {
    public let fileName: String
    public let problems: [CourseProblem]

    public var description: String {
        "\(fileName): " + problems.map(\.description).joined(separator: "; ")
    }
}

extension CourseFile {
    /// Course inclines steeper than this are treated as corrupt data rather than a real road.
    static let maximumPlausibleInclinePercent = 30.0

    /// Number of elevation samples for a course: one every `spacing` meters from 0, plus one at the finish.
    static func expectedSampleCount(distanceMeters: Double, spacingMeters: Double) -> Int {
        let gaps = distanceMeters / spacingMeters
        let wholeGaps = abs(gaps - gaps.rounded()) < 1e-9 ? gaps.rounded() : gaps.rounded(.up)
        return Int(wholeGaps) + 1
    }

    /// Returns every validation problem, or an empty array if the file is valid. Assumes the schema version has
    /// already been checked.
    func problems(fileName: String) -> [CourseProblem] {
        var problems: [CourseProblem] = []

        if id.isEmpty || !id.allSatisfy({ ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }) {
            problems.append(.invalidID(id))
        }
        if fileName != id + CourseLoader.fileSuffix {
            problems.append(.idDoesNotMatchFileName(id: id, fileName: fileName))
        }
        if name.isEmpty {
            problems.append(.emptyName)
        }

        let distanceIsValid = distanceMeters.isFinite && distanceMeters > 0
        if !distanceIsValid {
            problems.append(.invalidDistance(distanceMeters))
        }

        problems += inclineChangeProblems(distanceIsValid: distanceIsValid)
        problems += elevationProfileProblems(distanceIsValid: distanceIsValid)
        problems += statsProblems()
        problems += segmentProblems()
        return problems
    }

    private func inclineChangeProblems(distanceIsValid: Bool) -> [CourseProblem] {
        guard let first = inclineChanges.first else { return [.noInclineChanges] }
        var problems: [CourseProblem] = []
        if first.atMeters != 0 {
            problems.append(.firstInclineChangeNotAtStart(atMeters: first.atMeters))
        }
        for (index, change) in inclineChanges.enumerated() {
            if index > 0 {
                let previous = inclineChanges[index - 1]
                if !(change.atMeters > previous.atMeters) {
                    problems.append(.inclineChangeNotAfterPrevious(index: index))
                }
                if change.inclinePercent == previous.inclinePercent {
                    problems.append(.inclineRepeatsPrevious(index: index))
                }
            }
            if distanceIsValid && !(change.atMeters < distanceMeters) {
                problems.append(.inclineChangeNotBeforeFinish(index: index))
            }
            let incline = change.inclinePercent
            if !incline.isFinite || abs(incline) > Self.maximumPlausibleInclinePercent {
                problems.append(.inclineOutOfRange(index: index, inclinePercent: incline))
            } else if (incline * 2).rounded() != incline * 2 {
                problems.append(.inclineNotHalfPercent(index: index, inclinePercent: incline))
            }
        }
        return problems
    }

    private func elevationProfileProblems(distanceIsValid: Bool) -> [CourseProblem] {
        let spacing = elevationProfile.sampleSpacingMeters
        guard spacing.isFinite && spacing > 0 else { return [.invalidSampleSpacing(spacing)] }
        var problems: [CourseProblem] = []
        if distanceIsValid {
            let expected = Self.expectedSampleCount(distanceMeters: distanceMeters, spacingMeters: spacing)
            if elevationProfile.elevationsMeters.count != expected {
                problems.append(
                    .elevationSampleCountMismatch(expected: expected, actual: elevationProfile.elevationsMeters.count))
            }
        }
        // JSON can't express non-finite numbers, but a file built in code (as the pipeline will) can.
        for (index, elevation) in elevationProfile.elevationsMeters.enumerated() where !elevation.isFinite {
            problems.append(.elevationNotFinite(index: index))
        }
        return problems
    }

    private func statsProblems() -> [CourseProblem] {
        let values = [
            stats.elevationGainMeters, stats.elevationLossMeters, stats.minimumElevationMeters,
            stats.maximumElevationMeters,
        ]
        guard values.allSatisfy(\.isFinite) else { return [.invalidStats("values must be finite")] }
        var problems: [CourseProblem] = []
        if stats.elevationGainMeters < 0 || stats.elevationLossMeters < 0 {
            problems.append(.invalidStats("gain and loss must not be negative"))
        }
        if stats.minimumElevationMeters > stats.maximumElevationMeters {
            problems.append(.invalidStats("minimum elevation exceeds maximum"))
        }
        return problems
    }

    private func segmentProblems() -> [CourseProblem] {
        var problems: [CourseProblem] = []
        var seenIDs: Set<String> = []
        for (index, segment) in segments.enumerated() {
            if segment.id.isEmpty {
                problems.append(.emptySegmentID(index: index))
            } else if !seenIDs.insert(segment.id).inserted {
                problems.append(.duplicateSegmentID(segment.id))
            }
            if segment.name.isEmpty {
                problems.append(.emptySegmentName(index: index))
            }
            if !(segment.startMeters >= 0 && segment.startMeters < segment.endMeters
                && segment.endMeters <= distanceMeters)
            {
                problems.append(.segmentOutOfRange(index: index))
            }
        }
        return problems
    }
}

extension Course {
    /// Builds a course from a file that has passed validation.
    init(validated file: CourseFile) {
        let changes = file.inclineChanges
        let spacing = file.elevationProfile.sampleSpacingMeters
        let elevations = file.elevationProfile.elevationsMeters

        id = file.id
        name = file.name
        edition = file.edition
        location = file.location
        distanceMeters = file.distanceMeters
        isDevelopmentOnly = file.developmentOnly
        description = file.description
        source = CourseSource(
            route: SourceReference(
                name: file.source.route.name, url: file.source.route.url, license: file.source.route.license),
            elevation: ElevationSource(
                name: file.source.elevation.name, url: file.source.elevation.url,
                license: file.source.elevation.license, kind: file.source.elevation.kind),
            attribution: file.source.attribution,
            isVerified: file.source.verified,
            notes: file.source.notes)
        processing = CourseProcessing(
            tool: file.processing.tool, generatedOn: file.processing.generatedOn,
            parameters: file.processing.parameters)
        stats = CourseStats(
            elevationGainMeters: file.stats.elevationGainMeters,
            elevationLossMeters: file.stats.elevationLossMeters,
            minimumElevationMeters: file.stats.minimumElevationMeters,
            maximumElevationMeters: file.stats.maximumElevationMeters)
        elevationProfile = elevations.indices.map { index in
            let isLast = index == elevations.count - 1
            return ElevationSample(
                distanceMeters: isLast ? file.distanceMeters : Double(index) * spacing,
                elevationMeters: elevations[index])
        }
        inclineIntervals = changes.indices.map { index in
            CourseInclineInterval(
                startMeters: changes[index].atMeters,
                endMeters: index + 1 < changes.count ? changes[index + 1].atMeters : file.distanceMeters,
                inclinePercent: changes[index].inclinePercent)
        }
        curatedSegments = file.segments.map { segment in
            CourseSegment(
                id: segment.id, name: segment.name, kind: .curated, startMeters: segment.startMeters,
                endMeters: segment.endMeters)
        }
    }
}
