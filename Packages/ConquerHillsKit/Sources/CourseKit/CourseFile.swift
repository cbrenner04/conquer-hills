import Foundation

/// The on-disk JSON representation of a course, schema version 1. See `docs/course-format.md`.
///
/// Decoding is strict: a field that isn't part of the schema is rejected rather than ignored, so a typo in a
/// generated or hand-edited file surfaces instead of silently dropping data. Optional fields may be omitted or
/// `null`; every other field is required.
///
/// The type is public so the offline course pipeline (`Tools/CourseTool`) writes files through the same
/// definition the app reads; see `jsonData()`.
public struct CourseFile: Codable, Equatable, Sendable {
    public static let supportedSchemaVersion = 1

    public var schemaVersion: Int
    public var id: String
    public var name: String
    public var edition: String
    public var location: String
    public var distanceMeters: Double
    public var developmentOnly: Bool
    public var description: String?
    public var source: Source
    public var processing: Processing
    public var stats: Stats
    public var elevationProfile: ElevationProfile
    public var inclineChanges: [InclineChange]
    public var segments: [Segment]

    public init(
        schemaVersion: Int = CourseFile.supportedSchemaVersion, id: String, name: String, edition: String,
        location: String, distanceMeters: Double, developmentOnly: Bool, description: String?, source: Source,
        processing: Processing, stats: Stats, elevationProfile: ElevationProfile, inclineChanges: [InclineChange],
        segments: [Segment]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.edition = edition
        self.location = location
        self.distanceMeters = distanceMeters
        self.developmentOnly = developmentOnly
        self.description = description
        self.source = source
        self.processing = processing
        self.stats = stats
        self.elevationProfile = elevationProfile
        self.inclineChanges = inclineChanges
        self.segments = segments
    }

    public struct Source: Codable, Equatable, Sendable {
        public var route: Reference
        public var elevation: Elevation
        public var attribution: String?
        public var verified: Bool
        public var notes: String?

        public init(route: Reference, elevation: Elevation, attribution: String?, verified: Bool, notes: String?) {
            self.route = route
            self.elevation = elevation
            self.attribution = attribution
            self.verified = verified
            self.notes = notes
        }
    }

    public struct Reference: Codable, Equatable, Sendable {
        public var name: String
        public var url: String?
        public var license: String

        public init(name: String, url: String?, license: String) {
            self.name = name
            self.url = url
            self.license = license
        }
    }

    public struct Elevation: Codable, Equatable, Sendable {
        public var name: String
        public var url: String?
        public var license: String
        public var kind: ElevationSource.Kind

        public init(name: String, url: String?, license: String, kind: ElevationSource.Kind) {
            self.name = name
            self.url = url
            self.license = license
            self.kind = kind
        }
    }

    public struct Processing: Codable, Equatable, Sendable {
        public var tool: String
        public var generatedOn: String
        /// Free-form record of the settings the pipeline used; any keys are allowed.
        public var parameters: [String: String]

        public init(tool: String, generatedOn: String, parameters: [String: String]) {
            self.tool = tool
            self.generatedOn = generatedOn
            self.parameters = parameters
        }
    }

    public struct Stats: Codable, Equatable, Sendable {
        public var elevationGainMeters: Double
        public var elevationLossMeters: Double
        public var minimumElevationMeters: Double
        public var maximumElevationMeters: Double

        public init(
            elevationGainMeters: Double, elevationLossMeters: Double, minimumElevationMeters: Double,
            maximumElevationMeters: Double
        ) {
            self.elevationGainMeters = elevationGainMeters
            self.elevationLossMeters = elevationLossMeters
            self.minimumElevationMeters = minimumElevationMeters
            self.maximumElevationMeters = maximumElevationMeters
        }
    }

    public struct ElevationProfile: Codable, Equatable, Sendable {
        public var sampleSpacingMeters: Double
        public var elevationsMeters: [Double]

        public init(sampleSpacingMeters: Double, elevationsMeters: [Double]) {
            self.sampleSpacingMeters = sampleSpacingMeters
            self.elevationsMeters = elevationsMeters
        }
    }

    public struct InclineChange: Codable, Equatable, Sendable {
        public var atMeters: Double
        public var inclinePercent: Double

        public init(atMeters: Double, inclinePercent: Double) {
            self.atMeters = atMeters
            self.inclinePercent = inclinePercent
        }
    }

    public struct Segment: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var startMeters: Double
        public var endMeters: Double

        public init(id: String, name: String, startMeters: Double, endMeters: Double) {
            self.id = id
            self.name = name
            self.startMeters = startMeters
            self.endMeters = endMeters
        }
    }
}

// MARK: - Writing

/// Thrown when asked to write a file in a schema version this code can't produce.
public struct UnsupportedSchemaVersionError: Error, Equatable {
    public let schemaVersion: Int
}

extension CourseFile {
    /// The file as JSON in a stable layout (sorted keys, pretty-printed), so regenerating unchanged data produces
    /// byte-identical output. Throws if `schemaVersion` isn't the version this code writes. It does not validate
    /// the content: load the result back with `CourseLoader.load(_:fileName:)` to do that.
    public func jsonData() throws -> Data {
        guard schemaVersion == Self.supportedSchemaVersion else {
            throw UnsupportedSchemaVersionError(schemaVersion: schemaVersion)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self) + Data("\n".utf8)
    }
}

// MARK: - Strict decoding

/// Thrown while decoding when an object contains a field the schema doesn't define.
struct UnknownFieldError: Error {
    let codingPath: [any CodingKey]
}

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

extension Decoder {
    /// Returns a keyed container, first throwing `UnknownFieldError` if the object has any key not in `Keys`.
    fileprivate func strictContainer<Keys: CodingKey & CaseIterable>(
        keyedBy: Keys.Type
    ) throws -> KeyedDecodingContainer<Keys> {
        let known = Set(Keys.allCases.map(\.stringValue))
        let unknown = try container(keyedBy: AnyCodingKey.self).allKeys
            .filter { !known.contains($0.stringValue) }
            .sorted { $0.stringValue < $1.stringValue }
        if let first = unknown.first {
            throw UnknownFieldError(codingPath: codingPath + [first])
        }
        return try container(keyedBy: Keys.self)
    }
}

extension CourseFile {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, id, name, edition, location, distanceMeters, developmentOnly, description
        case source, processing, stats, elevationProfile, inclineChanges, segments
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.strictContainer(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        edition = try container.decode(String.self, forKey: .edition)
        location = try container.decode(String.self, forKey: .location)
        distanceMeters = try container.decode(Double.self, forKey: .distanceMeters)
        developmentOnly = try container.decode(Bool.self, forKey: .developmentOnly)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        source = try container.decode(Source.self, forKey: .source)
        processing = try container.decode(Processing.self, forKey: .processing)
        stats = try container.decode(Stats.self, forKey: .stats)
        elevationProfile = try container.decode(ElevationProfile.self, forKey: .elevationProfile)
        inclineChanges = try container.decode([InclineChange].self, forKey: .inclineChanges)
        segments = try container.decode([Segment].self, forKey: .segments)
    }
}

extension CourseFile.Source {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case route, elevation, attribution, verified, notes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.strictContainer(keyedBy: CodingKeys.self)
        route = try container.decode(CourseFile.Reference.self, forKey: .route)
        elevation = try container.decode(CourseFile.Elevation.self, forKey: .elevation)
        attribution = try container.decodeIfPresent(String.self, forKey: .attribution)
        verified = try container.decode(Bool.self, forKey: .verified)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }
}

extension CourseFile.Reference {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case name, url, license
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.strictContainer(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        license = try container.decode(String.self, forKey: .license)
    }
}

extension CourseFile.Elevation {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case name, url, license, kind
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.strictContainer(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        license = try container.decode(String.self, forKey: .license)
        kind = try container.decode(ElevationSource.Kind.self, forKey: .kind)
    }
}

extension CourseFile.Processing {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case tool, generatedOn, parameters
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.strictContainer(keyedBy: CodingKeys.self)
        tool = try container.decode(String.self, forKey: .tool)
        generatedOn = try container.decode(String.self, forKey: .generatedOn)
        parameters = try container.decode([String: String].self, forKey: .parameters)
    }
}

extension CourseFile.Stats {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case elevationGainMeters, elevationLossMeters, minimumElevationMeters, maximumElevationMeters
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.strictContainer(keyedBy: CodingKeys.self)
        elevationGainMeters = try container.decode(Double.self, forKey: .elevationGainMeters)
        elevationLossMeters = try container.decode(Double.self, forKey: .elevationLossMeters)
        minimumElevationMeters = try container.decode(Double.self, forKey: .minimumElevationMeters)
        maximumElevationMeters = try container.decode(Double.self, forKey: .maximumElevationMeters)
    }
}

extension CourseFile.ElevationProfile {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case sampleSpacingMeters, elevationsMeters
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.strictContainer(keyedBy: CodingKeys.self)
        sampleSpacingMeters = try container.decode(Double.self, forKey: .sampleSpacingMeters)
        elevationsMeters = try container.decode([Double].self, forKey: .elevationsMeters)
    }
}

extension CourseFile.InclineChange {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case atMeters, inclinePercent
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.strictContainer(keyedBy: CodingKeys.self)
        atMeters = try container.decode(Double.self, forKey: .atMeters)
        inclinePercent = try container.decode(Double.self, forKey: .inclinePercent)
    }
}

extension CourseFile.Segment {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, name, startMeters, endMeters
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.strictContainer(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        startMeters = try container.decode(Double.self, forKey: .startMeters)
        endMeters = try container.decode(Double.self, forKey: .endMeters)
    }
}
