import Foundation
import Testing

@testable import CourseToolCore

/// The point `east` and `north` meters from (35, 139).
private func at(_ east: Double, _ north: Double) -> Coordinate {
    let metersPerDegree = Geo.earthRadiusMeters * .pi / 180
    return Coordinate(
        latitude: 35 + north / metersPerDegree, longitude: 139 + east / (metersPerDegree * cos(35 * .pi / 180)))
}

private func waypoint(_ name: String, _ east: Double, _ north: Double) -> NamedPoint {
    NamedPoint(name: name, location: at(east, north))
}

private func road(_ id: Int, _ nodes: [Int], tags: [String: String] = [:]) -> RouteGraph.Way {
    RouteGraph.Way(id: id, version: 1, nodes: nodes, tags: ["highway": "residential"].merging(tags) { $1 })
}

@Suite("Route graph")
struct RouteGraphTests {
    /// Nodes on a 1 km square: 1 (0,0), 2 (1000,0), 3 (1000,1000), 4 (0,1000), plus 5 (500,0).
    let square: [Int: Coordinate] = [
        1: at(0, 0), 2: at(1000, 0), 3: at(1000, 1000), 4: at(0, 1000), 5: at(500, 0),
    ]

    @Test("A one-way street is used against its direction")
    func oneWayIgnored() throws {
        let ways = [road(10, [1, 2], tags: ["oneway": "yes"])]

        let result = try RouteGraph.route(
            through: [waypoint("east", 1000, 0), waypoint("west", 0, 0)], ways: ways, nodes: square,
            settings: .init())

        #expect(abs(result.lengthMeters - 1000) < 1)
        #expect(result.wayIDs == [10])
    }

    @Test("Stacked decks at the same coordinates are told apart by avoidWays")
    func stackedDecks() throws {
        // Two decks share coordinates but not nodes: 1–2 upper, 11–12 lower.
        var nodes = square
        nodes[11] = square[1]
        nodes[12] = square[2]
        let ways = [
            road(20, [1, 2], tags: ["layer": "3"]), road(21, [11, 12], tags: ["layer": "2"]),
        ]
        let points = [waypoint("west", 0, 0), waypoint("east", 1000, 0)]

        let upper = try RouteGraph.route(through: points, ways: ways, nodes: nodes, settings: .init(avoidWays: [21]))
        let lower = try RouteGraph.route(through: points, ways: ways, nodes: nodes, settings: .init(avoidWays: [20]))

        #expect(upper.wayIDs == [20])
        #expect(lower.wayIDs == [21])
    }

    @Test("A waypoint in the middle of a way turns the route around there")
    func outAndBack() throws {
        let ways = [road(30, [1, 2])]

        let result = try RouteGraph.route(
            through: [waypoint("start", 0, 0), waypoint("turnaround", 700, 3), waypoint("finish", 0, 0)], ways: ways,
            nodes: square, settings: .init())

        #expect(abs(result.lengthMeters - 1400) < 1)
        let farthest = result.line.map { Geo.distance($0, at(0, 0)) }.max() ?? 0
        #expect(abs(farthest - 700) < 1)
    }

    @Test("Two waypoints on the same way stay on it")
    func twoWaypointsOneWay() throws {
        let result = try RouteGraph.route(
            through: [waypoint("a", 200, 0), waypoint("b", 800, 0)], ways: [road(31, [1, 2])], nodes: square,
            settings: .init())

        #expect(abs(result.lengthMeters - 600) < 1)
    }

    @Test("Separately mapped sidewalks aren't used, even as a shortcut")
    func sidewalksExcluded() throws {
        let ways = [
            road(40, [1, 4]), road(41, [4, 3]), road(42, [3, 2]),
            RouteGraph.Way(id: 43, version: 1, nodes: [1, 2], tags: ["highway": "footway", "footway": "sidewalk"]),
        ]

        let result = try RouteGraph.route(
            through: [waypoint("west", 0, 0), waypoint("east", 1000, 0)], ways: ways, nodes: square,
            settings: .init(highways: ["residential", "footway"]))

        #expect(result.wayIDs == [40, 41, 42])
        #expect(abs(result.lengthMeters - 3000) < 1)
    }

    @Test("A listed way outside the highway network is used")
    func includeWays() throws {
        let ways = [
            road(50, [1, 5]),
            RouteGraph.Way(id: 51, version: 1, nodes: [5, 2], tags: ["barrier": "city_wall"]),
        ]
        let points = [waypoint("west", 0, 0), waypoint("east", 1000, 0)]

        let result = try RouteGraph.route(
            through: points, ways: ways, nodes: square, settings: .init(includeWays: [51]))

        #expect(result.wayIDs == [50, 51])
        #expect(throws: PipelineError.self) {
            try RouteGraph.route(through: points, ways: ways, nodes: square, settings: .init())
        }
    }

    @Test("A preferred way wins over a slightly shorter parallel way")
    func preferWays() throws {
        // Direct 1–2 (1000 m) against 1–4–3–2 (3000 m) would always lose; use a gentle detour instead.
        var nodes = square
        nodes[6] = at(500, 100)
        let ways = [road(60, [1, 2]), road(61, [1, 6, 2])]
        let points = [waypoint("west", 0, 0), waypoint("east", 1000, 0)]

        let plain = try RouteGraph.route(through: points, ways: ways, nodes: nodes, settings: .init())
        let preferred = try RouteGraph.route(
            through: points, ways: ways, nodes: nodes, settings: .init(preferWays: [61]))

        #expect(plain.wayIDs == [60])
        #expect(preferred.wayIDs == [61])
    }

    @Test("A gap in the corridor fails with the waypoints it couldn't join")
    func disconnected() {
        let ways = [road(70, [1, 5]), road(71, [2, 3])]

        #expect {
            try RouteGraph.route(
                through: [waypoint("west", 0, 0), waypoint("north-east", 1000, 1000)], ways: ways, nodes: square,
                settings: .init())
        } throws: { error in
            (error as? PipelineError)?.description.contains("\"west\" to \"north-east\"") == true
        }
    }

    @Test("A waypoint far from every usable way fails")
    func waypointOffRoute() {
        #expect(throws: PipelineError.self) {
            try RouteGraph.route(
                through: [waypoint("west", 0, 0), waypoint("field", 500, 400)], ways: [road(80, [1, 2])],
                nodes: square, settings: .init())
        }
    }

    @Test("osmGraph settings decode next to the route kind, with defaults")
    func decodesSettings() throws {
        let json = #"{"kind": "osmGraph", "avoidWays": [46858888], "corridorMeters": 150}"#
        let source = try JSONDecoder().decode(CourseConfig.RouteSource.self, from: Data(json.utf8))

        #expect(source == .osmGraph(.init(corridorMeters: 150, avoidWays: [46_858_888])))
        let roundTrip = try JSONDecoder().decode(
            CourseConfig.RouteSource.self, from: try JSONEncoder().encode(source))
        #expect(roundTrip == source)
    }
}
