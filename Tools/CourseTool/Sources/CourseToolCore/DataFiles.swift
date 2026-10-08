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

/// Waypoints are authored by hand, so they stay in readable GeoJSON.
public enum GeoJSON {
    /// Ordered waypoints from a FeatureCollection of Point features with a `name` property.
    public static func readWaypoints(_ data: Data) throws -> [NamedPoint] {
        let collection = try JSONDecoder().decode(FeatureCollection.self, from: data)
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
        return try PipelineJSON.encodeReadable(collection)
    }

    struct FeatureCollection: Codable, Sendable {
        var type = "FeatureCollection"
        var features: [Feature]
    }

    struct Feature: Codable, Sendable {
        var type = "Feature"
        var properties: [String: String]
        var geometry: PointGeometry
    }

    struct PointGeometry: Codable, Sendable {
        var type = "Point"
        var coordinates: [Double]
    }
}

/// The routed course line: `route.json`. Stored as a precision-6 encoded polyline (~0.1 m), so the geometry is
/// rounded exactly once, when written; everything downstream uses the decoded, rounded points.
public struct RouteFile: Codable, Equatable, Sendable {
    public var encoding = "polyline6"
    public var polyline: String
    /// Provenance: router or relation, licence, attribution, OSM timestamp.
    public var properties: [String: String]

    public init(line: [Coordinate], properties: [String: String]) {
        self.polyline = Polyline.encode(line)
        self.properties = properties
    }

    public var line: [Coordinate] { Polyline.decode(polyline) }
}

/// Bridges, tunnels and covered ways the route runs along: `osm-structures.json`.
///
/// Computed by the `route` step from OSM geometry and stored as distance ranges along the measured route (the
/// smoothed line, before calibration), the same axis elevation samples use.
public struct StructuresFile: Codable, Equatable, Sendable {
    public struct Span: Codable, Equatable, Sendable {
        /// `bridge`, `tunnel`, or `covered`.
        public var kind: String
        public var osmWayId: Int
        public var name: String?
        /// The way's OSM `highway` value, so the build can ignore expressways or underground concourses.
        public var highway: String
        public var startMeters: Double
        public var endMeters: Double

        public init(
            kind: String, osmWayId: Int, name: String?, highway: String, startMeters: Double, endMeters: Double
        ) {
            self.kind = kind
            self.osmWayId = osmWayId
            self.name = name
            self.highway = highway
            self.startMeters = startMeters
            self.endMeters = endMeters
        }
    }

    /// OSM data timestamp reported by Overpass, for provenance.
    public var osmTimestamp: String
    /// The structure settings the spans were computed with; changing them in the config requires rerunning
    /// `route`.
    public var settings: CourseConfig.StructureSettings
    public var routeFingerprint: String
    public var spans: [Span]

    public init(
        osmTimestamp: String, settings: CourseConfig.StructureSettings, routeFingerprint: String, spans: [Span]
    ) {
        self.osmTimestamp = osmTimestamp
        self.settings = settings
        self.routeFingerprint = routeFingerprint
        self.spans = spans.sorted { ($0.startMeters, $0.osmWayId) < ($1.startMeters, $1.osmWayId) }
    }
}

/// Elevation looked up along the route: `elevation-samples.json`.
///
/// Sample positions aren't stored: they are recomputed exactly from the stored route (`RouteSampling`). Each
/// sample has an elevation and a one-character source code; the codes are listed in `sources`. Filled
/// incrementally, so a run can resume.
public struct ElevationSamplesFile: Codable, Equatable, Sendable {
    /// Source code of a sample that hasn't been fetched yet.
    public static let notFetched: Character = "?"

    public var provider: String
    /// Identifies the route geometry and settings the samples belong to; a mismatch means they are stale.
    public var routeFingerprint: String
    public var routeSmoothingMeters: Double
    public var sampleSpacingMeters: Double
    /// Date the last sample was fetched (YYYY-MM-DD); becomes the course file's `generatedOn`.
    public var fetchedOn: String?
    /// Code → the provider's source label (e.g. GSI `hsrc`), used to judge quality.
    public var sources: [String: String]
    /// One code per sample, in order; `?` means not fetched yet.
    public var sourceCodes: String
    /// One elevation per sample, in meters as returned by the provider; nil where it has no data or before fetching.
    public var elevations: [Double?]

    public init(
        provider: String, routeFingerprint: String, routeSmoothingMeters: Double, sampleSpacingMeters: Double,
        count: Int
    ) {
        self.provider = provider
        self.routeFingerprint = routeFingerprint
        self.routeSmoothingMeters = routeSmoothingMeters
        self.sampleSpacingMeters = sampleSpacingMeters
        self.fetchedOn = nil
        self.sources = [:]
        self.sourceCodes = String(repeating: Self.notFetched, count: count)
        self.elevations = [Double?](repeating: nil, count: count)
    }

    public var count: Int { elevations.count }

    public var isComplete: Bool { !sourceCodes.contains(Self.notFetched) }

    /// Indices of samples still to fetch.
    public var missing: [Int] {
        sourceCodes.enumerated().compactMap { $0.element == Self.notFetched ? $0.offset : nil }
    }

    /// The source label of each sample (nil if not fetched).
    public var sourceLabels: [String?] { sourceCodes.map { sources[String($0)] } }

    /// Records a reading, assigning a new code to a source label the first time it's seen.
    public mutating func record(_ elevation: Double?, source: String, at index: Int) {
        let code: String
        if let existing = sources.first(where: { $0.value == source })?.key {
            code = existing
        } else {
            let alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
            let used = Set(sources.keys)
            guard let next = alphabet.map(String.init).first(where: { !used.contains($0) }) else {
                preconditionFailure("too many distinct elevation sources")
            }
            code = next
            sources[code] = source
        }
        var characters = Array(sourceCodes)
        characters[index] = Character(code)
        sourceCodes = String(characters)
        elevations[index] = elevation
    }

    /// Combines the stored values with sample positions recomputed from the route.
    public func samples(at positions: [RouteSampling.Position]) throws -> [ElevationSamplesFile.Sample] {
        guard positions.count == count else {
            throw PipelineError("\(count) elevation samples but the route gives \(positions.count) positions")
        }
        let labels = sourceLabels
        return positions.indices.map {
            Sample(
                distanceMeters: positions[$0].distanceMeters, location: positions[$0].location,
                elevationMeters: elevations[$0], source: labels[$0])
        }
    }

    /// One sample in memory: position (recomputed), elevation and source label (stored).
    public struct Sample: Equatable, Sendable {
        /// Meters along the measured route, before calibration.
        public var distanceMeters: Double
        public var location: Coordinate
        public var elevationMeters: Double?
        public var source: String?

        public init(distanceMeters: Double, location: Coordinate, elevationMeters: Double?, source: String?) {
            self.distanceMeters = distanceMeters
            self.location = location
            self.elevationMeters = elevationMeters
            self.source = source
        }
    }
}

/// Google's encoded polyline format at precision 6 (as OSRM's `polyline6`).
public enum Polyline {
    public static func encode(_ line: [Coordinate], precision: Double = 1e6) -> String {
        var result = ""
        var previous = (0, 0)
        for c in line {
            let lat = Int((c.latitude * precision).rounded())
            let lon = Int((c.longitude * precision).rounded())
            append(lat - previous.0, to: &result)
            append(lon - previous.1, to: &result)
            previous = (lat, lon)
        }
        return result
    }

    public static func decode(_ text: String, precision: Double = 1e6) -> [Coordinate] {
        var result: [Coordinate] = []
        var bytes = Array(text.utf8)[...]
        var lat = 0
        var lon = 0
        while !bytes.isEmpty {
            lat += next(&bytes)
            lon += next(&bytes)
            result.append(Coordinate(latitude: Double(lat) / precision, longitude: Double(lon) / precision))
        }
        return result
    }

    private static func append(_ value: Int, to result: inout String) {
        var v = value < 0 ? ~(value << 1) : value << 1
        while v >= 0x20 {
            result.unicodeScalars.append(UnicodeScalar(UInt8((0x20 | (v & 0x1f)) + 63)))
            v >>= 5
        }
        result.unicodeScalars.append(UnicodeScalar(UInt8(v + 63)))
    }

    private static func next(_ bytes: inout ArraySlice<UInt8>) -> Int {
        var result = 0
        var shift = 0
        while let byte = bytes.popFirst() {
            let chunk = Int(byte) - 63
            result |= (chunk & 0x1f) << shift
            shift += 5
            if chunk < 0x20 { break }
        }
        return (result & 1) != 0 ? ~(result >> 1) : result >> 1
    }
}

/// Reads and writes the pipeline's JSON files. Machine-written files are compact; authored ones are readable.
public enum PipelineJSON {
    public static func decode<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    /// Compact, with sorted keys so output is stable.
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value) + Data("\n".utf8)
    }

    /// Pretty-printed, for files people edit.
    public static func encodeReadable<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value) + Data("\n".utf8)
    }

    public static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try encode(value).write(to: url, options: .atomic)
    }
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
