import Foundation

/// A checkpoint found on the route.
public struct LocatedCheckpoint: Equatable, Sendable {
    public var checkpoint: CourseConfig.Checkpoint
    /// Index of the nearest elevation sample.
    public var sampleIndex: Int
    /// Distance along the measured route, before calibration.
    public var rawMeters: Double
    /// How far the checkpoint's location is from the route.
    public var offRouteMeters: Double
}

/// One stretch between consecutive checkpoints: traced length vs official length.
public struct CalibrationSection: Equatable, Sendable {
    public var fromName: String
    public var toName: String
    public var officialMeters: Double
    public var rawMeters: Double
    public var errorMeters: Double { rawMeters - officialMeters }
}

/// Maps distance along the traced route to official course distance, piecewise linearly between anchors.
public struct Calibration: Equatable, Sendable {
    /// (raw, official) pairs, strictly increasing in both.
    public let anchors: [(raw: Double, official: Double)]

    public static func == (lhs: Calibration, rhs: Calibration) -> Bool {
        lhs.anchors.elementsEqual(rhs.anchors) { $0.raw == $1.raw && $0.official == $1.official }
    }

    public init(anchors: [(raw: Double, official: Double)]) throws {
        guard anchors.count >= 2 else { throw PipelineError("calibration needs at least two anchors") }
        for (a, b) in zip(anchors, anchors.dropFirst()) where !(b.raw > a.raw && b.official > a.official) {
            throw PipelineError(
                "calibration anchors out of order near official \(Int(b.official)) m (raw \(Int(a.raw)) → \(Int(b.raw)))"
            )
        }
        self.anchors = anchors
    }

    /// Anchors: the start, every anchor checkpoint, and the finish. If the last anchor checkpoint is the finish
    /// itself, it ends the course and anything traced beyond it is dropped.
    public init(located: [LocatedCheckpoint], rawTotal: Double, officialTotal: Double) throws {
        var anchors: [(raw: Double, official: Double)] = [(0, 0)]
        for point in located where point.checkpoint.anchor {
            anchors.append((point.rawMeters, point.checkpoint.officialMeters))
        }
        if anchors.last!.official != officialTotal {
            anchors.append((rawTotal, officialTotal))
        }
        try self.init(anchors: anchors)
    }

    /// Raw distance where the official course ends.
    public var rawEnd: Double { anchors.last!.raw }

    public func official(forRaw raw: Double) -> Double {
        var i = 0
        while i < anchors.count - 2 && raw > anchors[i + 1].raw { i += 1 }
        let a = anchors[i]
        let b = anchors[i + 1]
        return a.official + (raw - a.raw) * (b.official - a.official) / (b.raw - a.raw)
    }

    /// Scale factor (official / raw) of each anchor section, for the record.
    public var sectionScales: [(fromOfficial: Double, toOfficial: Double, scale: Double)] {
        zip(anchors, anchors.dropFirst()).map { a, b in
            (a.official, b.official, (b.official - a.official) / (b.raw - a.raw))
        }
    }
}

public enum Checkpoints {
    /// Finds each checkpoint on the route, in course order.
    ///
    /// Searching starts after the previous checkpoint, so places the route passes more than once (both
    /// directions of an out-and-back, a bridge crossed twice) resolve to the right pass. Within the first stretch
    /// of samples inside `radiusMeters`, the nearest sample wins; at a turnaround that is the turning point.
    public static func locate(
        _ checkpoints: [CourseConfig.Checkpoint], samples: [ElevationSamplesFile.Sample], radiusMeters: Double
    ) throws -> [LocatedCheckpoint] {
        var result: [LocatedCheckpoint] = []
        var searchFrom = 0
        for checkpoint in checkpoints {
            var best: (index: Int, distance: Double)?
            var index = searchFrom
            while index < samples.count {
                let d = Geo.distance(samples[index].location, checkpoint.location)
                if d <= radiusMeters {
                    if best == nil || d < best!.distance { best = (index, d) }
                } else if best != nil {
                    break
                }
                index += 1
            }
            guard let best else {
                throw PipelineError(
                    "checkpoint \(checkpoint.name) (\(Int(checkpoint.officialMeters)) m) is not within "
                        + "\(Int(radiusMeters)) m of the route after the previous checkpoint")
            }
            result.append(
                LocatedCheckpoint(
                    checkpoint: checkpoint, sampleIndex: best.index, rawMeters: samples[best.index].distanceMeters,
                    offRouteMeters: best.distance))
            searchFrom = best.index + 1
        }
        return result
    }

    /// Traced vs official length of each stretch: start → first checkpoint → … → last checkpoint → finish.
    public static func sections(
        _ located: [LocatedCheckpoint], rawEnd: Double, officialTotal: Double
    ) -> [CalibrationSection] {
        var sections: [CalibrationSection] = []
        var previous = (name: "Start", raw: 0.0, official: 0.0)
        for point in located {
            sections.append(
                CalibrationSection(
                    fromName: previous.name, toName: point.checkpoint.name,
                    officialMeters: point.checkpoint.officialMeters - previous.official,
                    rawMeters: point.rawMeters - previous.raw))
            previous = (point.checkpoint.name, point.rawMeters, point.checkpoint.officialMeters)
        }
        if previous.official < officialTotal {
            sections.append(
                CalibrationSection(
                    fromName: previous.name, toName: "Finish", officialMeters: officialTotal - previous.official,
                    rawMeters: rawEnd - previous.raw))
        }
        return sections
    }
}
