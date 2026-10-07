import Foundation

/// The on-disk JSON representation of a course, schema version 1. See `docs/course-format.md`.
///
/// Decoding is strict: a field that isn't part of the schema is rejected rather than ignored, so a typo in a
/// generated or hand-edited file surfaces instead of silently dropping data. Optional fields may be omitted or
/// `null`; every other field is required.
struct CourseFile: Codable, Equatable, Sendable {
    static let supportedSchemaVersion = 1

    var schemaVersion: Int
    var id: String
    var name: String
    var edition: String
    var location: String
    var distanceMeters: Double
    var developmentOnly: Bool
    var description: String?
    var source: Source
    var processing: Processing
    var stats: Stats
    var elevationProfile: ElevationProfile
    var inclineChanges: [InclineChange]
    var segments: [Segment]

    struct Source: Codable, Equatable, Sendable {
        var route: Reference
        var elevation: Elevation
        var attribution: String?
        var verified: Bool
        var notes: String?
    }

    struct Reference: Codable, Equatable, Sendable {
        var name: String
        var url: String?
        var license: String
    }

    struct Elevation: Codable, Equatable, Sendable {
        var name: String
        var url: String?
        var license: String
        var kind: ElevationSource.Kind
    }

    struct Processing: Codable, Equatable, Sendable {
        var tool: String
        var generatedOn: String
        /// Free-form record of the settings the pipeline used; any keys are allowed.
        var parameters: [String: String]
    }

    struct Stats: Codable, Equatable, Sendable {
        var elevationGainMeters: Double
        var elevationLossMeters: Double
        var minimumElevationMeters: Double
        var maximumElevationMeters: Double
    }

    struct ElevationProfile: Codable, Equatable, Sendable {
        var sampleSpacingMeters: Double
        var elevationsMeters: [Double]
    }

    struct InclineChange: Codable, Equatable, Sendable {
        var atMeters: Double
        var inclinePercent: Double
    }

    struct Segment: Codable, Equatable, Sendable {
        var id: String
        var name: String
        var startMeters: Double
        var endMeters: Double
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

    init(from decoder: any Decoder) throws {
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

    init(from decoder: any Decoder) throws {
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

    init(from decoder: any Decoder) throws {
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

    init(from decoder: any Decoder) throws {
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

    init(from decoder: any Decoder) throws {
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

    init(from decoder: any Decoder) throws {
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

    init(from decoder: any Decoder) throws {
        let container = try decoder.strictContainer(keyedBy: CodingKeys.self)
        sampleSpacingMeters = try container.decode(Double.self, forKey: .sampleSpacingMeters)
        elevationsMeters = try container.decode([Double].self, forKey: .elevationsMeters)
    }
}

extension CourseFile.InclineChange {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case atMeters, inclinePercent
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.strictContainer(keyedBy: CodingKeys.self)
        atMeters = try container.decode(Double.self, forKey: .atMeters)
        inclinePercent = try container.decode(Double.self, forKey: .inclinePercent)
    }
}

extension CourseFile.Segment {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, name, startMeters, endMeters
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.strictContainer(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        startMeters = try container.decode(Double.self, forKey: .startMeters)
        endMeters = try container.decode(Double.self, forKey: .endMeters)
    }
}
