import CourseKit
import Foundation

/// Everything the pipeline needs to know about one course: `CourseData/<id>/config.json`.
public struct CourseConfig: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var edition: String
    public var location: String
    public var description: String?
    /// Official course distance; calibrated distances end exactly here.
    public var officialDistanceMeters: Double
    public var source: CourseFile.Source
    public var route: RouteSource
    public var elevation: ElevationSettings
    public var structures: StructureSettings
    public var processing: ProcessingSettings
    /// Official checkpoints, in course order.
    public var checkpoints: [Checkpoint]
    /// Stretches where the measured elevation is overridden: interpolated, or kept as measured even if flagged.
    public var manualSpans: [ManualSpan]
    public var segments: [CourseFile.Segment]
    public var acceptance: [AcceptanceCheck]

    /// Where the route geometry comes from.
    public enum RouteSource: Codable, Equatable, Sendable {
        /// Hand-picked waypoints (`waypoints.geojson`) snapped to OSM roads by an OSRM-compatible router.
        case waypoints(routerBaseURL: String)
        /// An OpenStreetMap route relation; its member ways are chained into one line starting near `start`.
        case osmRelation(id: Int, start: Coordinate)

        private enum CodingKeys: String, CodingKey { case kind, routerBaseURL, relationId, start }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(String.self, forKey: .kind) {
            case "waypoints":
                self = .waypoints(routerBaseURL: try container.decode(String.self, forKey: .routerBaseURL))
            case "osmRelation":
                self = .osmRelation(
                    id: try container.decode(Int.self, forKey: .relationId),
                    start: try container.decode(Coordinate.self, forKey: .start))
            case let other:
                throw DecodingError.dataCorruptedError(
                    forKey: .kind, in: container, debugDescription: "unknown route kind \(other)")
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .waypoints(let url):
                try container.encode("waypoints", forKey: .kind)
                try container.encode(url, forKey: .routerBaseURL)
            case .osmRelation(let id, let start):
                try container.encode("osmRelation", forKey: .kind)
                try container.encode(id, forKey: .relationId)
                try container.encode(start, forKey: .start)
            }
        }
    }

    public struct ElevationSettings: Codable, Equatable, Sendable {
        /// `gsi` (Japan, single-point API) or `usgs3dep` (United States).
        public var provider: String
        /// Source labels, as reported per sample by the provider, that are trusted. Others are interpolated.
        public var trustedSources: [String]
    }

    public struct StructureSettings: Codable, Equatable, Sendable {
        /// Samples within this distance of a bridge, tunnel or covered way running along the route are suspect.
        public var bufferMeters: Double
        /// A structure only counts where it runs within this many degrees of the route's direction, so bridges
        /// crossing over the route (footbridges, expressways) don't flag the road beneath them.
        public var maximumAngleDegrees: Double
        /// OSM `highway` values that are never part of the route (e.g. expressways overhead).
        public var ignoredHighways: [String]
        /// Tunnels and covered ways of these `highway` values are ignored: underground concourses and arcades run
        /// beneath or beside the street while the runner stays on the surface. Bridges always count, since the
        /// sidewalks on road bridges are mapped as footways.
        public var ignoredTunnelHighways: [String]
    }

    public struct ProcessingSettings: Codable, Equatable, Sendable {
        /// Moving-average window applied to the routed line, approximating the racing line.
        public var routeSmoothingMeters: Double
        /// Spacing of elevation samples along the route.
        public var sampleSpacingMeters: Double
        /// Moving-average window applied to elevation.
        public var smoothingWindowMeters: Double
        /// Length of the blocks grade is averaged over before rounding.
        public var gradeBlockMeters: Double
        /// Shortest incline interval kept; shorter ones are merged into a neighbour.
        public var minimumIntervalMeters: Double
        public var inclineStepPercent: Double
        /// Spacing of the chart samples written to the course file.
        public var profileSampleSpacingMeters: Double
        /// A stretch between consecutive checkpoints whose traced length differs from the official length by more
        /// than this means the route was traced down the wrong street.
        public var maximumSectionErrorMeters: Double
        /// 10 m elevation steps steeper than this (after cleaning) are listed for review.
        public var steepStepPercent: Double
        /// How far from its location a checkpoint may be and still be found on the route.
        public var checkpointSearchRadiusMeters: Double
    }

    public struct Checkpoint: Codable, Equatable, Sendable {
        public var name: String
        public var officialMeters: Double
        public var location: Coordinate
        /// Anchors pin the distance calibration. Use exact course features (turnarounds, bridges, the finish);
        /// markers named after nearby buildings are checked and reported but don't anchor.
        public var anchor: Bool
    }

    public struct ManualSpan: Codable, Equatable, Sendable {
        public enum Action: String, Codable, Sendable {
            /// Replace with a straight line between trusted samples either side (false dips, missing data).
            case interpolate
            /// Keep the measured elevation even where samples would otherwise be flagged (real rises).
            case keep
        }

        /// Official (calibrated) course meters.
        public var startMeters: Double
        public var endMeters: Double
        public var action: Action
        public var reason: String
    }

    public struct AcceptanceCheck: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable {
            /// Smoothed elevation at `atMeters` within `min`...`max`.
            case elevationAt
            /// Highest smoothed elevation over `fromMeters`...`toMeters` at most `max`.
            case maximumElevation
            /// Elevation drop from `fromMeters` to `toMeters` within `min`...`max`.
            case drop
            /// Total gain within `min`...`max`.
            case gain
            /// Total loss within `min`...`max`.
            case loss
            /// gain − loss equals finish − start within `max`.
            case netBalance
            /// No course incline beyond ±`max` percent.
            case maximumIncline
            /// No dip around `atMeters` (± `radiusMeters`): the lowest point there isn't more than 0.5 m below
            /// the lower of the two edges.
            case noDip
        }

        public var name: String
        public var kind: Kind
        public var atMeters: Double?
        public var fromMeters: Double?
        public var toMeters: Double?
        public var radiusMeters: Double?
        public var min: Double?
        public var max: Double?
    }
}

/// Reads and writes the pipeline's JSON files in a stable, diff-friendly layout.
public enum PipelineJSON {
    public static func decode<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value) + Data("\n".utf8)
    }

    public static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try encode(value).write(to: url, options: .atomic)
    }
}
