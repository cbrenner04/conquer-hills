import Foundation

/// A named point: waypoints and checkpoints in GeoJSON files.
public struct NamedPoint: Equatable, Sendable {
    public var name: String
    public var location: Coordinate

    public init(name: String, location: Coordinate) {
        self.name = name
        self.location = location
    }
}

/// Minimal GeoJSON reading and writing for the pipeline's files (points and one line string).
public enum GeoJSON {
    /// Ordered waypoints from a FeatureCollection of Point features with a `name` property.
    public static func readWaypoints(_ data: Data) throws -> [NamedPoint] {
        let collection = try JSONDecoder().decode(FeatureCollection<PointGeometry>.self, from: data)
        return collection.features.map {
            NamedPoint(
                name: $0.properties["name"] ?? "",
                location: Coordinate(latitude: $0.geometry.coordinates[1], longitude: $0.geometry.coordinates[0]))
        }
    }

    public static func waypointsData(_ points: [NamedPoint]) throws -> Data {
        let collection = FeatureCollection(
            features: points.map {
                Feature(
                    properties: ["name": $0.name],
                    geometry: PointGeometry(coordinates: [$0.location.longitude, $0.location.latitude]))
            })
        return try PipelineJSON.encode(collection)
    }

    /// The route line from a FeatureCollection holding one LineString feature, plus its properties.
    public static func readRoute(_ data: Data) throws -> (line: [Coordinate], properties: [String: String]) {
        let collection = try JSONDecoder().decode(FeatureCollection<LineGeometry>.self, from: data)
        guard let feature = collection.features.first else { throw PipelineError("route file has no features") }
        return (
            feature.geometry.coordinates.map { Coordinate(latitude: $0[1], longitude: $0[0]) }, feature.properties
        )
    }

    public static func routeData(_ line: [Coordinate], properties: [String: String]) throws -> Data {
        // Seven decimal places (~1 cm) keeps the file stable and readable.
        let coordinates = line.map { [roundTo($0.longitude, places: 7), roundTo($0.latitude, places: 7)] }
        let collection = FeatureCollection(
            features: [Feature(properties: properties, geometry: LineGeometry(coordinates: coordinates))])
        return try PipelineJSON.encode(collection)
    }

    struct FeatureCollection<Geometry: Codable & Sendable>: Codable, Sendable {
        var type = "FeatureCollection"
        var features: [Feature<Geometry>]
    }

    struct Feature<Geometry: Codable & Sendable>: Codable, Sendable {
        var type = "Feature"
        var properties: [String: String]
        var geometry: Geometry
    }

    struct PointGeometry: Codable, Sendable {
        var type = "Point"
        var coordinates: [Double]
    }

    struct LineGeometry: Codable, Sendable {
        var type = "LineString"
        var coordinates: [[Double]]
    }
}

/// OSM bridges, tunnels and covered ways near the route: `osm-structures.json`.
public struct StructuresFile: Codable, Equatable, Sendable {
    public struct Way: Codable, Equatable, Sendable {
        public var id: Int
        public var tags: [String: String]
        public var geometry: [Coordinate]

        public init(id: Int, tags: [String: String], geometry: [Coordinate]) {
            self.id = id
            self.tags = tags
            self.geometry = geometry
        }
    }

    /// OSM data timestamp reported by Overpass, for provenance.
    public var osmTimestamp: String
    public var bufferMeters: Double
    public var ways: [Way]

    public init(osmTimestamp: String, bufferMeters: Double, ways: [Way]) {
        self.osmTimestamp = osmTimestamp
        self.bufferMeters = bufferMeters
        self.ways = ways.sorted { $0.id < $1.id }
    }
}

/// Elevation looked up along the route: `elevation-samples.json`. Filled incrementally, so a run can resume.
public struct ElevationSamplesFile: Codable, Equatable, Sendable {
    public struct Sample: Codable, Equatable, Sendable {
        /// Meters along the smoothed route, before calibration.
        public var distanceMeters: Double
        public var location: Coordinate
        /// nil until fetched, or if the provider has no data there (then `source` says so).
        public var elevationMeters: Double?
        /// The provider's label for where the value came from (e.g. GSI `hsrc`), used to judge quality.
        public var source: String?

        public init(distanceMeters: Double, location: Coordinate, elevationMeters: Double?, source: String?) {
            self.distanceMeters = distanceMeters
            self.location = location
            self.elevationMeters = elevationMeters
            self.source = source
        }

        public var isFetched: Bool { source != nil }
    }

    public var provider: String
    /// Identifies the route geometry and settings the sample positions were computed from; a mismatch means
    /// the samples are stale and must be refetched.
    public var routeFingerprint: String
    public var routeSmoothingMeters: Double
    public var sampleSpacingMeters: Double
    /// Date the last sample was fetched (YYYY-MM-DD); becomes the course file's `generatedOn`.
    public var fetchedOn: String?
    public var samples: [Sample]

    public var isComplete: Bool { samples.allSatisfy(\.isFetched) }
}

public struct PipelineError: Error, CustomStringConvertible, Equatable {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}

func roundTo(_ value: Double, places: Int) -> Double {
    let scale = pow(10, Double(places))
    let rounded = (value * scale).rounded() / scale
    return rounded == 0 ? 0 : rounded
}

/// Stable 64-bit FNV-1a hash, as hex. Used to fingerprint route geometry; not for security.
public func fingerprint(_ text: String) -> String {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in text.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x0000_0100_0000_01b3
    }
    return String(hash, radix: 16)
}
