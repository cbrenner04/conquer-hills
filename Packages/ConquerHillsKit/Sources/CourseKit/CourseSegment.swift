/// A continuous part of a course, from `startMeters` up to `endMeters`, in absolute course positions.
public struct CourseSegment: Identifiable, Equatable, Sendable, Codable {
    public enum Kind: String, Equatable, Sendable, Codable {
        /// The whole course.
        case fullCourse
        /// Generated for every course long enough to have it (halves, first and final 5K).
        case standard
        /// Supplied with the course data.
        case curated
        /// Chosen by the runner.
        case custom
    }

    public let id: String
    /// Display name; nil for a custom segment.
    public let name: String?
    public let kind: Kind
    public let startMeters: Double
    public let endMeters: Double

    public var distanceMeters: Double { endMeters - startMeters }

    init(id: String, name: String?, kind: Kind, startMeters: Double, endMeters: Double) {
        self.id = id
        self.name = name
        self.kind = kind
        self.startMeters = startMeters
        self.endMeters = endMeters
    }
}

extension Course {
    /// Courses at least this long get the half and 5K standard segments.
    static let standardSegmentMinimumMeters = 10_000.0
    static let fiveKMeters = 5_000.0

    public var fullCourseSegment: CourseSegment {
        CourseSegment(
            id: "full-course", name: "Full course", kind: .fullCourse, startMeters: 0, endMeters: distanceMeters)
    }

    /// The full course, then (for courses of 10 km or more) first half, second half, first 5K, and final 5K.
    public var standardSegments: [CourseSegment] {
        guard distanceMeters >= Self.standardSegmentMinimumMeters else { return [fullCourseSegment] }
        let half = distanceMeters / 2
        return [
            fullCourseSegment,
            CourseSegment(id: "first-half", name: "First half", kind: .standard, startMeters: 0, endMeters: half),
            CourseSegment(
                id: "second-half", name: "Second half", kind: .standard, startMeters: half, endMeters: distanceMeters),
            CourseSegment(
                id: "first-5k", name: "First 5K", kind: .standard, startMeters: 0, endMeters: Self.fiveKMeters),
            CourseSegment(
                id: "final-5k", name: "Final 5K", kind: .standard, startMeters: distanceMeters - Self.fiveKMeters,
                endMeters: distanceMeters),
        ]
    }

    /// Standard segments followed by curated ones: the predefined choices offered for this course.
    public var predefinedSegments: [CourseSegment] { standardSegments + curatedSegments }

    /// A runner-chosen segment, or nil unless `0 ≤ startMeters < endMeters ≤ distanceMeters`.
    ///
    /// Minimum segment length and boundary precision are UI concerns and are not enforced here.
    public func customSegment(startMeters: Double, endMeters: Double) -> CourseSegment? {
        guard startMeters >= 0, startMeters < endMeters, endMeters <= distanceMeters else { return nil }
        return CourseSegment(
            id: "custom-\(startMeters)-\(endMeters)", name: nil, kind: .custom, startMeters: startMeters,
            endMeters: endMeters)
    }

    /// Whether `segment` lies within this course.
    public func contains(_ segment: CourseSegment) -> Bool {
        segment.startMeters >= 0 && segment.startMeters < segment.endMeters && segment.endMeters <= distanceMeters
    }
}
