/// A real-world running course: its metadata, elevation profile, and course incline.
///
/// Courses are created only by `CourseLoader`, so every `Course` has passed validation. Distances are meters
/// from the start of the course.
public struct Course: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    /// Display string identifying the version of the route, usually the race year.
    public let edition: String
    public let location: String
    public let distanceMeters: Double
    /// True for test data that only appears in development builds.
    public let isDevelopmentOnly: Bool
    public let description: String?
    public let source: CourseSource
    public let processing: CourseProcessing
    public let stats: CourseStats
    /// Evenly spaced elevation samples from the start to the finish, for charts. Not used by the workout engine.
    public let elevationProfile: [ElevationSample]
    /// The course incline as contiguous intervals covering the whole course.
    public let inclineIntervals: [CourseInclineInterval]
    /// Named segments supplied with the course data.
    public let curatedSegments: [CourseSegment]
}

/// A stretch of course with a constant course incline.
public struct CourseInclineInterval: Equatable, Sendable {
    public let startMeters: Double
    public let endMeters: Double
    /// Smoothed grade of the real course, in percent. Negative values are downhill.
    public let inclinePercent: Double

    public init(startMeters: Double, endMeters: Double, inclinePercent: Double) {
        self.startMeters = startMeters
        self.endMeters = endMeters
        self.inclinePercent = inclinePercent
    }
}

public struct ElevationSample: Equatable, Sendable {
    public let distanceMeters: Double
    public let elevationMeters: Double

    public init(distanceMeters: Double, elevationMeters: Double) {
        self.distanceMeters = distanceMeters
        self.elevationMeters = elevationMeters
    }
}

/// Where a course's data came from, for attribution and honesty about accuracy.
public struct CourseSource: Equatable, Sendable {
    public let route: SourceReference
    public let elevation: ElevationSource
    /// Text the app must display when a data license requires attribution.
    public let attribution: String?
    /// Whether a person has checked the route against official material.
    public let isVerified: Bool
    public let notes: String?
}

public struct SourceReference: Equatable, Sendable {
    public let name: String
    public let url: String?
    public let license: String
}

public struct ElevationSource: Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        /// Surveyed or recorded on the ground.
        case measured
        /// Derived from a terrain model.
        case modeled
    }

    public let name: String
    public let url: String?
    public let license: String
    public let kind: Kind
}

/// How the course file was produced, so it can be traced and regenerated.
public struct CourseProcessing: Equatable, Sendable {
    public let tool: String
    public let generatedOn: String
    public let parameters: [String: String]
}

/// Elevation statistics computed by the data pipeline from its full-resolution data.
public struct CourseStats: Equatable, Sendable {
    public let elevationGainMeters: Double
    public let elevationLossMeters: Double
    public let minimumElevationMeters: Double
    public let maximumElevationMeters: Double
}
