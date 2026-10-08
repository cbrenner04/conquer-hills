import Testing

@testable import CourseToolCore

@Suite("Geometry")
struct GeoTests {
    @Test("Great-circle distance between known points")
    func knownDistance() {
        // One degree of latitude is about 111.2 km.
        let d = Geo.distance(Coordinate(latitude: 35, longitude: 139), Coordinate(latitude: 36, longitude: 139))
        #expect(abs(d - 111_195) < 10)
    }

    @Test("Resampling places points every 10 m along the line, around corners, and keeps both ends")
    func resampleSpacing() {
        let line = [Geo.Point(x: 0, y: 0), Geo.Point(x: 25, y: 0), Geo.Point(x: 25, y: 12)]

        let points = Geo.resample(line, every: 10)

        // 0, 10, 20 along the first leg; 30 is 5 m up the second leg; then the end point.
        #expect(
            points == [
                Geo.Point(x: 0, y: 0), Geo.Point(x: 10, y: 0), Geo.Point(x: 20, y: 0), Geo.Point(x: 25, y: 5),
                Geo.Point(x: 25, y: 12),
            ])
    }

    @Test("Smoothing leaves a straight line straight and keeps its ends")
    func smoothStraightLine() {
        let line = [Geo.Point(x: 0, y: 0), Geo.Point(x: 500, y: 0)]
        let smoothed = Geo.smoothLine(line, windowMeters: 40)

        #expect(smoothed.allSatisfy { abs($0.y) < 1e-9 })
        #expect(abs(Geo.cumulativeDistances(smoothed).last! - 500) < 1e-6)
        #expect(smoothed.first == line.first)
        #expect(smoothed.last == line.last)
    }

    @Test("Smoothing flattens a junction zigzag, shortening the line toward the racing line")
    func smoothZigzag() {
        // A straight 400 m road with a 15 m jog out to a junction centre and back.
        let line = [
            Geo.Point(x: 0, y: 0), Geo.Point(x: 195, y: 0), Geo.Point(x: 200, y: 15), Geo.Point(x: 205, y: 0),
            Geo.Point(x: 400, y: 0),
        ]
        let raw = Geo.cumulativeDistances(line).last!
        let smoothed = Geo.cumulativeDistances(Geo.smoothLine(line, windowMeters: 40)).last!

        #expect(raw > 420)
        #expect(smoothed < raw)
        #expect(smoothed < 405)
    }

    @Test("Simplification drops points within tolerance and keeps corners")
    func simplify() {
        let line = (0...100).map { Geo.Point(x: Double($0), y: 0) } + [Geo.Point(x: 100, y: 50)]
        let simplified = Geo.simplify(line, toleranceMeters: 1)

        #expect(simplified == [Geo.Point(x: 0, y: 0), Geo.Point(x: 100, y: 0), Geo.Point(x: 100, y: 50)])
    }
}

@Suite("Relation chaining")
struct RelationChainingTests {
    let nodes: [Int: Coordinate] = Dictionary(
        uniqueKeysWithValues: (1...7).map { ($0, Coordinate(latitude: 35, longitude: 139 + Double($0) * 0.001)) })

    @Test("Shuffled and reversed member ways chain into one line from the start")
    func chainsOutOfOrder() throws {
        let ways = [
            RelationChaining.Way(id: 30, nodes: [7, 6, 5]),  // reversed
            RelationChaining.Way(id: 10, nodes: [1, 2, 3]),
            RelationChaining.Way(id: 20, nodes: [3, 4, 5]),
        ]

        let chained = try RelationChaining.chain(ways: ways, nodeLocations: nodes, start: nodes[1]!)

        #expect(chained == [1, 2, 3, 4, 5, 6, 7])
    }

    @Test("Starts from whichever end is nearest the start line")
    func startsAtNearestEnd() throws {
        let ways = [RelationChaining.Way(id: 10, nodes: [1, 2, 3]), RelationChaining.Way(id: 20, nodes: [3, 4])]

        let chained = try RelationChaining.chain(ways: ways, nodeLocations: nodes, start: nodes[4]!)

        #expect(chained == [4, 3, 2, 1])
    }

    @Test("A gap between member ways is an error")
    func gap() {
        let ways = [RelationChaining.Way(id: 10, nodes: [1, 2]), RelationChaining.Way(id: 20, nodes: [5, 6])]

        #expect(throws: PipelineError.self) {
            try RelationChaining.chain(ways: ways, nodeLocations: nodes, start: nodes[1]!)
        }
    }
}
