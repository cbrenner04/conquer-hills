import Foundation

/// Joins the member ways of an OpenStreetMap route relation into one line.
///
/// Relation members are often stored out of order and in either direction. Ways are chained by shared end nodes,
/// starting from the way end nearest the course start.
public enum RelationChaining {
    public struct Way: Equatable, Sendable {
        public var id: Int
        public var nodes: [Int]

        public init(id: Int, nodes: [Int]) {
            self.id = id
            self.nodes = nodes
        }
    }

    /// The ordered node IDs of the chained route.
    public static func chain(ways: [Way], nodeLocations: [Int: Coordinate], start: Coordinate) throws -> [Int] {
        let usable = ways.filter { $0.nodes.count >= 2 }
        guard !usable.isEmpty else { throw PipelineError("relation has no ways") }

        func location(_ node: Int) throws -> Coordinate {
            guard let c = nodeLocations[node] else { throw PipelineError("relation is missing node \(node)") }
            return c
        }

        // Begin at the way end closest to the start line.
        var best: (wayIndex: Int, reversed: Bool, distance: Double)?
        for (index, way) in usable.enumerated() {
            for reversed in [false, true] {
                let end = reversed ? way.nodes.last! : way.nodes.first!
                let d = Geo.distance(try location(end), start)
                if best == nil || d < best!.distance {
                    best = (index, reversed, d)
                }
            }
        }
        var used = Set([best!.wayIndex])
        var route = best!.reversed ? usable[best!.wayIndex].nodes.reversed() : usable[best!.wayIndex].nodes

        while used.count < usable.count {
            let end = route.last!
            guard
                let next = usable.indices.first(where: {
                    !used.contains($0) && (usable[$0].nodes.first == end || usable[$0].nodes.last == end)
                })
            else {
                let remaining = usable.indices.filter { !used.contains($0) }.map { usable[$0].id }
                throw PipelineError(
                    "relation route has a gap after node \(end); unconnected ways: \(remaining.prefix(10))")
            }
            used.insert(next)
            let nodes = usable[next].nodes.first == end ? usable[next].nodes : usable[next].nodes.reversed()
            route.append(contentsOf: nodes.dropFirst())
        }
        return route
    }
}

/// One elevation lookup result.
public struct ElevationReading: Equatable, Sendable {
    /// nil when the provider has no data at the point.
    public var elevationMeters: Double?
    /// The provider's label for the data source at that point (e.g. GSI's `hsrc`), used to judge quality.
    public var source: String

    public init(elevationMeters: Double?, source: String) {
        self.elevationMeters = elevationMeters
        self.source = source
    }
}

/// An elevation data source. Implementations live in the `course-tool` executable (they use the network).
public protocol ElevationProvider: Sendable {
    /// The value written to `elevation-samples.json` and matched against `config.elevation.provider`.
    var name: String { get }
    /// How many points one call should be given.
    var batchSize: Int { get }
    /// Elevations for `points`, in order, one reading per point.
    func elevations(at points: [Coordinate]) async throws -> [ElevationReading]
}
