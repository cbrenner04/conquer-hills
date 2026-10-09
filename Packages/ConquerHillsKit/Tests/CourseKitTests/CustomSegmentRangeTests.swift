import Testing

@testable import CourseKit

@Suite("Custom segment range")
struct CustomSegmentRangeTests {
    private let mile = CustomSegmentRange.metersPerMile
    private let marathon = 42195.0

    private func isClose(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-6 }

    @Test("Starts as the whole course")
    func wholeCourse() {
        let range = CustomSegmentRange(courseMeters: marathon)

        #expect(range.startMeters == 0)
        #expect(range.endMeters == marathon)
        #expect(!range.canMoveStartEarlier)
        #expect(!range.canMoveEndLater)
    }

    @Test("Boundaries move in 0.1 mile steps")
    func steps() {
        var range = CustomSegmentRange(courseMeters: marathon)
        range.moveStart(bySteps: 100)  // 10 mi
        range.moveStart(bySteps: 3)
        range.moveEnd(bySteps: -10)

        #expect(isClose(range.startMeters, 10.3 * mile))
        #expect(isClose(range.endMeters, 25.2 * mile))  // 26.22 snaps to the finish; −1 mi lands on the grid
    }

    @Test("The start can't go below 0 and the end can't pass the finish")
    func clampsToCourse() {
        var range = CustomSegmentRange(courseMeters: marathon)
        range.moveStart(bySteps: -5)
        range.moveEnd(bySteps: 5)

        #expect(range.startMeters == 0)
        #expect(range.endMeters == marathon)
    }

    @Test("Boundaries keep at least 0.5 mi apart and can't cross")
    func minimumLength() {
        var range = CustomSegmentRange(courseMeters: marathon, startMeters: 10 * mile, endMeters: 12 * mile)
        range.moveStart(bySteps: 50)

        #expect(isClose(range.startMeters, 11.5 * mile))
        #expect(!range.canMoveStartLater)

        range.moveEnd(bySteps: -50)
        #expect(isClose(range.endMeters, 12 * mile))
        #expect(!range.canMoveEndEarlier)
        #expect(range.distanceMeters >= CustomSegmentRange.minimumMeters - 1e-6)
    }

    @Test("Moving the end back from the finish lands on the 0.1 mile grid")
    func endFromFinish() {
        var range = CustomSegmentRange(courseMeters: marathon)
        range.moveEnd(bySteps: -1)

        #expect(isClose(range.endMeters, 26.1 * mile))
        range.moveEnd(bySteps: 1)
        #expect(range.endMeters == marathon)
    }

    @Test("Initial boundaries are snapped and made valid")
    func initialSnapping() {
        let range = CustomSegmentRange(courseMeters: marathon, startMeters: 10.04 * mile, endMeters: 10.2 * mile)

        #expect(isClose(range.startMeters, 9.7 * mile))
        #expect(isClose(range.endMeters, 10.2 * mile))
    }

    @Test("A course shorter than the minimum is one whole range")
    func shortCourse() {
        var range = CustomSegmentRange(courseMeters: 600)
        range.moveStart(bySteps: 1)

        #expect(range.startMeters == 0)
        #expect(range.endMeters == 600)
    }

    @Test("The range becomes a custom segment of the course")
    func segment() throws {
        let course = try Fixture.course(Fixture.json(distance: 5000, changes: [(0, 0)]))
        var range = CustomSegmentRange(courseMeters: course.distanceMeters)
        range.moveStart(bySteps: 5)

        let segment = try #require(range.segment(in: course))
        #expect(segment.kind == .custom)
        #expect(isClose(segment.startMeters, 0.5 * mile))
        #expect(segment.endMeters == 5000)
    }
}

@Suite("Elevation chart data")
struct ElevationChartDataTests {
    private func samples(_ elevations: [Double], spacing: Double = 100) -> [ElevationSample] {
        elevations.enumerated().map {
            ElevationSample(distanceMeters: Double($0.offset) * spacing, elevationMeters: $0.element)
        }
    }

    @Test("Downsampling keeps the ends and the highest and lowest points")
    func downsampleKeepsExtremes() {
        var elevations = Array(repeating: 10.0, count: 500)
        elevations[123] = 80
        elevations[377] = -5
        let input = samples(elevations)

        let output = ElevationChartData.downsample(input, maximumPoints: 40)

        #expect(output.count <= 40)
        #expect(output.first == input.first)
        #expect(output.last == input.last)
        #expect(output.contains(input[123]))
        #expect(output.contains(input[377]))
        #expect(output.map(\.distanceMeters) == output.map(\.distanceMeters).sorted())
    }

    @Test("Short profiles are returned unchanged")
    func downsampleShort() {
        let input = samples([1, 2, 3])
        #expect(ElevationChartData.downsample(input, maximumPoints: 60) == input)
    }

    @Test("A slice adds interpolated samples exactly at both ends")
    func slice() {
        let input = samples([0, 10, 20, 30])

        let slice = ElevationChartData.slice(input, from: 50, to: 250)

        #expect(slice.map(\.distanceMeters) == [50, 100, 200, 250])
        #expect(slice.map(\.elevationMeters) == [5, 10, 20, 25])
    }

    @Test("Interpolation clamps outside the profile")
    func interpolationClamps() {
        let input = samples([0, 10])
        #expect(ElevationChartData.elevation(at: -10, in: input) == 0)
        #expect(ElevationChartData.elevation(at: 500, in: input) == 10)
    }
}
