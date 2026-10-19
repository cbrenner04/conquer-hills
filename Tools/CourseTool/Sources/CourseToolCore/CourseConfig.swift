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
        /// Hand-picked waypoints (`waypoints.geojson`) routed by `RouteGraph` over OSM ways fetched around them,
        /// ignoring one-way and access tags. For courses no public router traces.
        case osmGraph(OSMGraphSettings)

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
            case "osmGraph":
                self = .osmGraph(try OSMGraphSettings(from: decoder))
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
            case .osmGraph(let settings):
                try container.encode("osmGraph", forKey: .kind)
                try settings.encode(to: encoder)
            }
        }
    }

    /// Settings for an `osmGraph` route, written next to `kind` in the config's `route` object.
    public struct OSMGraphSettings: Codable, Equatable, Sendable {
        /// Ways within this distance of the line through the waypoints are downloaded. Waypoints must be close
        /// enough together that the course stays inside it.
        public var corridorMeters: Double
        /// OSM `highway` values the route may use; nil means `RouteGraph.defaultHighways` (roads). Add `path`,
        /// `track`, `footway` or `cycleway` for trails and greenways. Sidewalks and crossings are never used.
        public var highways: [String]?
        /// Ways used whatever their tags, e.g. a city wall that isn't a `highway`.
        public var includeWays: [Int]
        /// Ways never used: the deck or carriageway the course doesn't take where roads are stacked or parallel.
        public var avoidWays: [Int]
        /// Ways that cost half their length, so the route takes them over a parallel alternative.
        public var preferWays: [Int]
        /// Straight links where OSM leaves a gap the course crosses (a path that stops short of the road across
        /// tram tracks). Each end snaps to the nearest OSM node of a usable way.
        public var joins: [Join]

        public struct Join: Codable, Equatable, Sendable {
            public var from: Coordinate
            public var to: Coordinate
            public var reason: String

            public init(from: Coordinate, to: Coordinate, reason: String) {
                self.from = from
                self.to = to
                self.reason = reason
            }
        }

        public init(
            corridorMeters: Double = 200, highways: [String]? = nil, includeWays: [Int] = [], avoidWays: [Int] = [],
            preferWays: [Int] = [], joins: [Join] = []
        ) {
            self.corridorMeters = corridorMeters
            self.highways = highways
            self.includeWays = includeWays
            self.avoidWays = avoidWays
            self.preferWays = preferWays
            self.joins = joins
        }

        private enum CodingKeys: String, CodingKey {
            case corridorMeters, highways, includeWays, avoidWays, preferWays, joins
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                corridorMeters: try container.decodeIfPresent(Double.self, forKey: .corridorMeters) ?? 200,
                highways: try container.decodeIfPresent([String].self, forKey: .highways),
                includeWays: try container.decodeIfPresent([Int].self, forKey: .includeWays) ?? [],
                avoidWays: try container.decodeIfPresent([Int].self, forKey: .avoidWays) ?? [],
                preferWays: try container.decodeIfPresent([Int].self, forKey: .preferWays) ?? [],
                joins: try container.decodeIfPresent([Join].self, forKey: .joins) ?? [])
        }
    }

    public struct ElevationSettings: Codable, Equatable, Sendable {
        /// `gsi` (Japan, single-point API), `usgs3dep` (United States), `gaDem5m` (Australia), `wmsPoint` (a WMS
        /// raster layer, configured by `wms`), `wcsGrid` (a WCS coverage as text grids, configured by `wcs`) `copernicus` (the global 30 m
        /// surface model, where nothing better exists) or `flat` (no measured data: every sample is `baseMeters`, labelled
        /// `flat`).
        public var provider: String
        /// Source labels, as reported per sample by the provider, that are trusted. Others are interpolated.
        public var trustedSources: [String]
        /// The service and response fields for `wmsPoint`.
        public var wms: WMSPointSettings?
        /// The coverage for `wcsGrid`.
        public var wcs: WCSGridSettings?
        /// The constant elevation for `flat`, where no usable open elevation data exists (Shanghai). Real bridge humps
        /// are added as modelled profiles (`riseMeters` in `profiles.json`).
        public var baseMeters: Double?
    }

    /// A WCS 2.0.1 coverage that `GetCoverage` serves as `text/plain` grids in EPSG:4326.
    public struct WCSGridSettings: Codable, Equatable, Sendable {
        /// The service URL without a query.
        public var url: String
        public var coverageId: String
        /// The source label for every sample (the service reports none).
        public var label: String
    }

    /// A WMS `GetFeatureInfo` service that returns a raster layer's raw value as JSON. Paths are dotted keys into the
    /// response, where numeric parts index arrays (e.g. `layers.0.raw.bands.0.value`).
    public struct WMSPointSettings: Codable, Equatable, Sendable {
        /// The service URL without a query.
        public var url: String
        public var layer: String
        /// The elevation in meters: a number or a numeric string. A point without one has no data.
        public var valuePath: String
        /// A mask value; where it is 0 the point has no data (e.g. sea, outside the survey).
        public var maskPath: String?
        /// The per-sample source label (e.g. the source raster's file name)…
        public var labelPath: String?
        /// …or a fixed label, for services that report none.
        public var label: String?
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
            /// Lowest smoothed elevation over `fromMeters`...`toMeters` at least `min` (e.g. no false dip at a river
            /// crossing that is also a real low point).
            case minimumElevation
            /// No course incline beyond ±`max` percent; with `fromMeters`/`toMeters`, no incline above `max` among
            /// intervals overlapping that window by at least 100 m (e.g. a level stretch between hills).
            case maximumIncline
            /// Some incline interval overlapping `fromMeters`...`toMeters` by at least 100 m climbs at `min` percent or
            /// more: the hill survives smoothing and merging as a climb.
            case climb
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
        /// For `gain`, `loss` and `netBalance`: measure on the cleaned elevation smoothed with this window instead
        /// of the build's window. Totals depend strongly on smoothing, so a range taken from another source must be
        /// compared at that source's smoothing. The course file's stats always use the build's window.
        public var smoothingWindowMeters: Double?
    }
}
