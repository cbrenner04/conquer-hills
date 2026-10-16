import Foundation

/// Routes through waypoints over OpenStreetMap ways the way a race uses them: on race day every road on the course
/// is open to runners in both directions, so one-way and access tags are ignored.
///
/// The graph holds the ways the settings allow (road classes, plus listed extra ways, minus avoided ones). Each
/// waypoint is snapped to the nearest point on any usable way, which may be in the middle of a way, and the route is
/// the shortest path from each waypoint to the next. A path may come back along the way it arrived on, so a waypoint
/// at a turnaround produces a U-turn. Stacked roads (bridge decks, underpasses) share coordinates, so they are told
/// apart by listing the deck to avoid or prefer, not by position.
public enum RouteGraph {
    /// An OSM way with its node IDs, tags and version.
    public struct Way: Equatable, Sendable {
        public var id: Int
        public var version: Int?
        public var nodes: [Int]
        public var tags: [String: String]

        public init(id: Int, version: Int?, nodes: [Int], tags: [String: String]) {
            self.id = id
            self.version = version
            self.nodes = nodes
            self.tags = tags
        }
    }

    public struct Result: Equatable, Sendable {
        public var line: [Coordinate]
        /// The ways the route uses, in order of first use.
        public var wayIDs: [Int]
        public var lengthMeters: Double
    }

    /// Road classes used when the settings don't list any.
    public static let defaultHighways = [
        "motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link", "secondary", "secondary_link",
        "tertiary", "tertiary_link", "unclassified", "residential", "living_street", "service", "pedestrian", "road",
    ]
    /// A waypoint farther than this from every usable way is an error, not a guess.
    public static let maximumSnapMeters = 50.0
    /// Preferred ways cost this fraction of their length, so a path takes them over a parallel way.
    public static let preferredCostFactor = 0.5

    /// Whether `way` belongs in the graph.
    public static func isUsable(_ way: Way, settings: CourseConfig.OSMGraphSettings) -> Bool {
        if settings.avoidWays.contains(way.id) { return false }
        if settings.includeWays.contains(way.id) { return true }
        let highways = settings.highways ?? defaultHighways
        guard let highway = way.tags["highway"], highways.contains(highway) else { return false }
        // Separately mapped sidewalks and crossings run beside the course, not on it.
        if let footway = way.tags["footway"], footway == "sidewalk" || footway == "crossing" { return false }
        if way.tags["area"] == "yes" { return false }
        return true
    }

    public static func route(
        through waypoints: [NamedPoint], ways: [Way], nodes: [Int: Coordinate],
        settings: CourseConfig.OSMGraphSettings
    ) throws -> Result {
        guard waypoints.count >= 2 else { throw PipelineError("a route needs at least two waypoints") }
        let usable = ways.filter { $0.nodes.count >= 2 && isUsable($0, settings: settings) }
        let projection = Geo.Projection(fitting: waypoints.map(\.location))

        // Graph nodes are OSM nodes, then one virtual node per waypoint.
        var index: [Int: Int] = [:]
        var points: [Geo.Point] = []
        var coordinates: [Coordinate] = []
        func node(_ id: Int) throws -> Int {
            if let i = index[id] { return i }
            guard let c = nodes[id] else { throw PipelineError("OSM node \(id) is missing from the downloaded data") }
            index[id] = points.count
            points.append(projection.point(c))
            coordinates.append(c)
            return points.count - 1
        }
        struct Segment {
            var a: Int
            var b: Int
            var way: Int
            var costFactor: Double
        }
        var segments: [Segment] = []
        for way in usable {
            let factor = settings.preferWays.contains(way.id) ? preferredCostFactor : 1
            for (a, b) in zip(way.nodes, way.nodes.dropFirst()) where a != b {
                segments.append(Segment(a: try node(a), b: try node(b), way: way.id, costFactor: factor))
            }
        }
        guard !segments.isEmpty else { throw PipelineError("no usable ways in the downloaded corridor") }

        // Snap each waypoint to the nearest point on any segment.
        var snaps: [Int: [(t: Double, node: Int)]] = [:]
        var waypointNodes: [Int] = []
        for waypoint in waypoints {
            let p = projection.point(waypoint.location)
            var best: (segment: Int, t: Double, distance: Double)?
            for (s, segment) in segments.enumerated() {
                let (t, d) = project(p, points[segment.a], points[segment.b])
                if best == nil || d < best!.distance { best = (s, t, d) }
            }
            guard let best, best.distance <= maximumSnapMeters else {
                throw PipelineError(
                    "waypoint \"\(waypoint.name)\" is \(Int(best?.distance ?? .infinity)) m from the nearest usable "
                        + "way (limit \(Int(maximumSnapMeters)) m): move it onto the course, or allow that way")
            }
            let a = points[segments[best.segment].a]
            let b = points[segments[best.segment].b]
            let virtual = points.count
            points.append(Geo.Point(x: a.x + (b.x - a.x) * best.t, y: a.y + (b.y - a.y) * best.t))
            coordinates.append(projection.coordinate(points[virtual]))
            snaps[best.segment, default: []].append((best.t, virtual))
            waypointNodes.append(virtual)
        }

        // Undirected adjacency; a segment carrying waypoints is split at them.
        var adjacency = [[(to: Int, length: Double, cost: Double, way: Int)]](repeating: [], count: points.count)
        func connect(_ a: Int, _ b: Int, _ segment: Segment) {
            let length = points[a].distance(to: points[b])
            adjacency[a].append((b, length, length * segment.costFactor, segment.way))
            adjacency[b].append((a, length, length * segment.costFactor, segment.way))
        }
        for (s, segment) in segments.enumerated() {
            let chain = [segment.a] + (snaps[s] ?? []).sorted { $0.t < $1.t }.map(\.node) + [segment.b]
            for (a, b) in zip(chain, chain.dropFirst()) { connect(a, b, segment) }
        }

        var path = [waypointNodes[0]]
        var wayIDs: [Int] = []
        var length = 0.0
        for leg in 0..<(waypointNodes.count - 1) {
            guard
                let (legPath, legWays) = shortestPath(
                    from: waypointNodes[leg], to: waypointNodes[leg + 1], adjacency: adjacency)
            else {
                throw PipelineError(
                    "no path from waypoint \"\(waypoints[leg].name)\" to \"\(waypoints[leg + 1].name)\" over usable "
                        + "ways: a way is missing from the corridor, excluded, or avoided")
            }
            for ((a, b), way) in zip(zip(legPath, legPath.dropFirst()), legWays) {
                let step = points[a].distance(to: points[b])
                length += step
                // Zero-length steps join a snapped waypoint to a junction; they don't use the way.
                if step > 0.01 && !wayIDs.contains(way) { wayIDs.append(way) }
            }
            path.append(contentsOf: legPath.dropFirst())
        }
        var line: [Coordinate] = []
        for i in path where line.last.map({ Geo.distance($0, coordinates[i]) > 0.01 }) ?? true {
            line.append(coordinates[i])
        }
        return Result(line: line, wayIDs: wayIDs, lengthMeters: length)
    }

    /// Where `p` projects onto the segment `a`–`b` (0...1) and how far it is from it.
    static func project(_ p: Geo.Point, _ a: Geo.Point, _ b: Geo.Point) -> (t: Double, distance: Double) {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return (0, p.distance(to: a)) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return (t, p.distance(to: Geo.Point(x: a.x + t * dx, y: a.y + t * dy)))
    }

    /// Dijkstra: the node path and the way of each step, or nil if `to` can't be reached.
    static func shortestPath(
        from: Int, to: Int, adjacency: [[(to: Int, length: Double, cost: Double, way: Int)]]
    ) -> (nodes: [Int], ways: [Int])? {
        if from == to { return ([from], []) }
        var cost = [Double](repeating: .infinity, count: adjacency.count)
        var previous = [(node: Int, way: Int)?](repeating: nil, count: adjacency.count)
        var heap = MinHeap()
        cost[from] = 0
        heap.push(0, from)
        while let (c, u) = heap.pop() {
            if u == to { break }
            if c > cost[u] { continue }
            for edge in adjacency[u] where c + edge.cost < cost[edge.to] {
                cost[edge.to] = c + edge.cost
                previous[edge.to] = (u, edge.way)
                heap.push(cost[edge.to], edge.to)
            }
        }
        guard cost[to] < .infinity else { return nil }
        var nodes = [to]
        var ways: [Int] = []
        var current = to
        while let step = previous[current] {
            nodes.append(step.node)
            ways.append(step.way)
            current = step.node
        }
        return (nodes.reversed(), ways.reversed())
    }

    /// A binary min-heap of (cost, node).
    struct MinHeap {
        private var items: [(Double, Int)] = []

        mutating func push(_ cost: Double, _ node: Int) {
            items.append((cost, node))
            var i = items.count - 1
            while i > 0 {
                let parent = (i - 1) / 2
                guard items[i].0 < items[parent].0 else { break }
                items.swapAt(i, parent)
                i = parent
            }
        }

        mutating func pop() -> (Double, Int)? {
            guard !items.isEmpty else { return nil }
            items.swapAt(0, items.count - 1)
            let top = items.removeLast()
            var i = 0
            while true {
                let left = 2 * i + 1
                let right = left + 1
                var smallest = i
                if left < items.count && items[left].0 < items[smallest].0 { smallest = left }
                if right < items.count && items[right].0 < items[smallest].0 { smallest = right }
                if smallest == i { break }
                items.swapAt(i, smallest)
                i = smallest
            }
            return top
        }
    }
}
