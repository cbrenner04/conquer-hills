import Foundation

/// Why a sample's measured elevation was replaced.
public enum SuspectReason: Equatable, Sendable, CustomStringConvertible {
    case noData
    case untrustedSource(String)
    case structure(wayID: Int, kind: String, name: String?)
    case manual(String)

    public var description: String {
        switch self {
        case .noData: "no data"
        case .untrustedSource(let source): "source \(source)"
        case .structure(let id, let kind, let name): "\(kind) \(name ?? "") (OSM way \(id))"
        case .manual(let reason): "manual: \(reason)"
        }
    }
}

/// A run of consecutive samples replaced by interpolation.
public struct InterpolatedSpan: Equatable, Sendable {
    public var startMeters: Double
    public var endMeters: Double
    public var reasons: [String]
}

/// A 10 m step steeper than the review threshold, after cleaning.
public struct SteepStep: Equatable, Sendable {
    public var atMeters: Double
    public var gradePercent: Double
}

public struct CleanedElevation: Equatable, Sendable {
    /// Official course distance of each sample.
    public var distances: [Double]
    public var measured: [Double?]
    public var cleaned: [Double]
    public var reasons: [SuspectReason?]
    public var spans: [InterpolatedSpan]
    public var steepSteps: [SteepStep]
}

public enum ElevationCleaning {
    /// For each sample, why it is suspect (or nil if it is trusted).
    public static func suspectReasons(
        samples: [ElevationSamplesFile.Sample], distances: [Double], trustedSources: [String],
        structures: [StructuresFile.Way], settings: CourseConfig.StructureSettings,
        manualSpans: [CourseConfig.ManualSpan]
    ) -> [SuspectReason?] {
        let projection = Geo.Projection(fitting: samples.map(\.location))
        let points = samples.map { projection.point($0.location) }
        let candidates = structures.filter { way in
            guard let highway = way.tags["highway"] else { return false }  // only roads and paths can be the route
            return !settings.ignoredHighways.contains(highway)
        }.map { way in (way: way, points: way.geometry.map(projection.point)) }

        var reasons = [SuspectReason?](repeating: nil, count: samples.count)
        for i in samples.indices {
            let sample = samples[i]
            if sample.elevationMeters == nil {
                reasons[i] = .noData
            } else if let source = sample.source, !trustedSources.contains(source) {
                reasons[i] = .untrustedSource(source)
            } else if let hit = structure(
                at: i, points: points, candidates: candidates, bufferMeters: settings.bufferMeters,
                maximumAngleDegrees: settings.maximumAngleDegrees)
            {
                reasons[i] = hit
            }
        }
        for span in manualSpans {
            for i in samples.indices where distances[i] >= span.startMeters && distances[i] <= span.endMeters {
                reasons[i] = span.action == .interpolate ? .manual(span.reason) : nil
            }
        }
        return reasons
    }

    /// The structure the route is on at sample `i`: within the buffer and running roughly along the route.
    static func structure(
        at i: Int, points: [Geo.Point], candidates: [(way: StructuresFile.Way, points: [Geo.Point])],
        bufferMeters: Double, maximumAngleDegrees: Double
    ) -> SuspectReason? {
        let p = points[i]
        let before = points[max(0, i - 2)]
        let after = points[min(points.count - 1, i + 2)]
        let routeAngle = atan2(after.y - before.y, after.x - before.x)
        for candidate in candidates {
            for (a, b) in zip(candidate.points, candidate.points.dropFirst())
            where Geo.distanceToSegment(p, a, b) <= bufferMeters {
                var difference = abs(atan2(b.y - a.y, b.x - a.x) - routeAngle).truncatingRemainder(dividingBy: .pi)
                difference = min(difference, .pi - difference)
                if difference * 180 / .pi <= maximumAngleDegrees {
                    let tags = candidate.way.tags
                    let kind =
                        tags["bridge"].map { _ in "bridge" } ?? tags["tunnel"].map { _ in "tunnel" } ?? "covered way"
                    return .structure(wayID: candidate.way.id, kind: kind, name: tags["name"])
                }
            }
        }
        return nil
    }

    /// Replaces suspect samples by linear interpolation between the nearest trusted samples. Suspect runs at the
    /// start or end take the nearest trusted value.
    public static func clean(
        samples: [ElevationSamplesFile.Sample], distances: [Double], reasons: [SuspectReason?],
        steepStepPercent: Double
    ) throws -> CleanedElevation {
        let trusted = samples.indices.filter { reasons[$0] == nil }
        guard !trusted.isEmpty else { throw PipelineError("no trusted elevation samples") }
        var cleaned = samples.map { $0.elevationMeters ?? 0 }
        var spans: [InterpolatedSpan] = []
        var i = 0
        while i < samples.count {
            guard reasons[i] != nil else {
                i += 1
                continue
            }
            var j = i
            while j + 1 < samples.count && reasons[j + 1] != nil { j += 1 }
            let left = i > 0 ? i - 1 : nil
            let right = j + 1 < samples.count ? j + 1 : nil
            for k in i...j {
                switch (left, right) {
                case (let l?, let r?):
                    let t = (distances[k] - distances[l]) / (distances[r] - distances[l])
                    cleaned[k] = cleaned[l] + t * (cleaned[r] - cleaned[l])
                case (let l?, nil): cleaned[k] = cleaned[l]
                case (nil, let r?): cleaned[k] = samples[r].elevationMeters!
                case (nil, nil): break
                }
            }
            var seen: [String] = []
            for k in i...j {
                let text = reasons[k]!.description
                if !seen.contains(text) { seen.append(text) }
            }
            spans.append(InterpolatedSpan(startMeters: distances[i], endMeters: distances[j], reasons: seen))
            i = j + 1
        }
        var steep: [SteepStep] = []
        for k in 1..<samples.count {
            let run = distances[k] - distances[k - 1]
            guard run > 0 else { continue }
            let grade = (cleaned[k] - cleaned[k - 1]) / run * 100
            if abs(grade) > steepStepPercent {
                steep.append(SteepStep(atMeters: distances[k - 1], gradePercent: grade))
            }
        }
        return CleanedElevation(
            distances: distances, measured: samples.map(\.elevationMeters), cleaned: cleaned, reasons: reasons,
            spans: spans, steepSteps: steep)
    }
}
