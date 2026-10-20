import Foundation

/// How long a course is, for grouping the course list. Longest first.
public enum CourseDistanceClass: Int, CaseIterable, Comparable, Sendable {
    case marathon
    case halfMarathon
    case fifteenK
    case tenK
    case short

    public init(meters: Double) {
        switch meters {
        case 40_000...: self = .marathon
        case 20_000..<40_000: self = .halfMarathon
        case 14_000..<20_000: self = .fifteenK
        case 9_500..<14_000: self = .tenK
        default: self = .short
        }
    }

    public var title: String {
        switch self {
        case .marathon: "Marathon"
        case .halfMarathon: "Half marathon"
        case .fifteenK: "15K and 10 miles"
        case .tenK: "10K to 8 miles"
        case .short: "Under 6 miles"
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Where a course is, read from its `location`: the text after the last comma is the country
/// (`"Hopkinton to Boston, Massachusetts, USA"` → United States), and the text before it is the city.
public enum CourseRegion {
    /// Countries the list knows, by display name. A course in any other country goes under "Other"; a test keeps
    /// every bundled course in a known country, so a typo in a new course's location fails the build.
    public static let knownCountries: Set<String> = [
        "United States", "Australia", "China", "Germany", "Japan", "South Africa", "United Kingdom",
    ]
    public static let other = "Other"

    /// The display name of `location`'s country, or nil if it names none the list knows.
    public static func country(of location: String) -> String? {
        let last = location.split(separator: ",").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        let name = ["USA": "United States", "US": "United States", "UK": "United Kingdom"][last] ?? last
        return knownCountries.contains(name) ? name : nil
    }

    /// `location` without its country: `"Hopkinton to Boston, Massachusetts"`. A location with no known country is
    /// returned whole.
    public static func city(of location: String) -> String {
        guard country(of: location) != nil, let comma = location.lastIndex(of: ",") else { return location }
        return location[..<comma].trimmingCharacters(in: .whitespaces)
    }
}

/// How the course list is sectioned.
public enum CourseGroupingMode: String, CaseIterable, Sendable {
    case distance
    case region

    public var title: String {
        switch self {
        case .distance: "Distance"
        case .region: "Region"
        }
    }
}

/// One section of the course list.
public struct CourseSection: Identifiable, Equatable, Sendable {
    public let title: String
    public let courses: [Course]
    public var id: String { title }
}

public enum CourseGrouping {
    /// The list's sections: by distance (longest first) or by country (United States first, then alphabetical,
    /// "Other" last), each sorted by name. Only courses matching `query` (in name or location, ignoring case and
    /// accents) appear, and empty sections are left out.
    public static func sections(_ courses: [Course], by mode: CourseGroupingMode, matching query: String = "")
        -> [CourseSection]
    {
        let shown = courses.filter { matches($0, query) }
        let sections: [(key: String, order: String, courses: [Course])]
        switch mode {
        case .distance:
            sections = Dictionary(grouping: shown) { CourseDistanceClass(meters: $0.distanceMeters) }
                .sorted { $0.key < $1.key }
                .map { (key: $0.key.title, order: "", courses: $0.value) }
        case .region:
            sections = Dictionary(grouping: shown) { CourseRegion.country(of: $0.location) ?? CourseRegion.other }
                .map { key, value in
                    let rank = key == "United States" ? "0" : key == CourseRegion.other ? "2" : "1"
                    return (key: key, order: rank + key, courses: value)
                }
                .sorted { $0.order < $1.order }
        }
        return sections.map { section in
            CourseSection(
                title: section.key,
                courses: section.courses.sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                })
        }
    }

    /// Whether `course`'s name or location contains `query`; an empty query matches everything.
    public static func matches(_ course: Course, _ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return course.name.range(of: query, options: options) != nil
            || course.location.range(of: query, options: options) != nil
    }
}
