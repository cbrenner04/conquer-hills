import Foundation
import Testing

@testable import CourseToolCore

@Suite("WCS grid elevations")
struct WCSGridTests {
    let settings = CourseConfig.WCSGridSettings(
        url: "https://environment.data.gov.uk/geoservices/datasets/13787b9a-26a4-4775-8523-806d13af58fc/wcs",
        coverageId: "13787b9a-26a4-4775-8523-806d13af58fc__Lidar_Composite_Elevation_DTM_1m", label: "ea-dtm-2022")

    /// A recorded response (2026-10-19): the Environment Agency's 1 m terrain model around the London Marathon's Blue
    /// start on Shooters Hill Road.
    static let blueStart = #"""
        Grid bounds: GeneralBounds[(0.01083873475370139, 51.472943339378226), (0.011046893141134715, 51.4730995559841)]
        Grid CRS: GEOGCS["WGS 84",
          DATUM["World Geodetic System 1984",
            SPHEROID["WGS 84", 6378137.0, 298.257223563, AUTHORITY["EPSG","7030"]],
            AUTHORITY["EPSG","6326"]],
          PRIMEM["Greenwich", 0.0, AUTHORITY["EPSG","8901"]],
          UNIT["degree", 0.017453292519943295],
          AXIS["Geodetic longitude", EAST],
          AXIS["Geodetic latitude", NORTH],
          AUTHORITY["EPSG","4326"]]
        Grid range: GeneralGridEnvelope[10..23, 11..27]
        Grid to world: PARAM_MT["Affine",
          PARAMETER["num_row", 3],
          PARAMETER["num_col", 3],
          PARAMETER["elt_0_0", 0.0000148684562452375],
          PARAMETER["elt_0_2", 0.010697484419371635],
          PARAMETER["elt_1_1", -0.00000918921211019311],
          PARAMETER["elt_1_2", 51.47319604271126]]
        Contents:
        Band 0:
        39.806 39.82 39.802 39.784 39.787 39.758 39.745 39.734 39.684 39.681 39.687 39.698 39.69 39.689
        39.75 39.754 39.71 39.673 39.673 39.678 39.677 39.693 39.661 39.676 39.693 39.701 39.713 39.712
        39.648 39.663 39.657 39.664 39.668 39.684 39.689 39.684 39.701 39.699 39.715 39.718 39.734 39.74
        39.664 39.66 39.683 39.695 39.71 39.694 39.7 39.721 39.724 39.729 39.728 39.722 39.741 39.756
        39.677 39.69 39.689 39.705 39.712 39.719 39.717 39.703 39.705 39.728 39.729 39.735 39.741 39.744
        39.706 39.692 39.693 39.716 39.709 39.74 39.736 39.738 39.726 39.729 39.736 39.745 39.743 39.779
        39.709 39.709 39.703 39.696 39.718 39.722 39.735 39.722 39.723 39.748 39.745 39.738 39.747 39.75
        39.698 39.71 39.702 39.712 39.727 39.72 39.733 39.726 39.724 39.73 39.723 39.731 39.74 39.747
        39.697 39.711 39.693 39.723 39.718 39.711 39.72 39.695 39.692 39.709 39.718 39.694 39.715 39.71
        39.69 39.698 39.713 39.714 39.693 39.692 39.699 39.684 39.695 39.682 39.689 39.694 39.677 39.688
        39.681 39.672 39.669 39.681 39.661 39.673 39.673 39.667 39.668 39.649 39.65 39.637 39.626 39.632
        39.658 39.659 39.638 39.639 39.631 39.638 39.629 39.618 39.614 39.612 39.611 39.588 39.591 39.606
        39.593 39.569 39.6 39.591 39.6 39.585 39.586 39.565 39.574 39.537 39.549 39.557 39.558 39.566
        39.568 39.529 39.551 39.55 39.543 39.542 39.532 39.538 39.52 39.527 39.539 39.587 39.643 39.676
        39.52 39.482 39.492 39.47 39.481 39.525 39.548 39.554 39.577 39.639 39.638 39.653 39.74 39.773
        39.49 39.486 39.494 39.492 39.486 39.521 39.544 39.559 39.561 39.6 39.634 39.665 39.7 39.691
        39.514 39.541 39.546 39.511 39.497 39.506 39.523 39.532 39.559 39.554 39.565 39.559 39.584 39.569
        """#

    /// A small synthetic grid: 3 columns × 2 rows of 1° cells, centres from (10°E, 51°N).
    static func synthetic(_ values: String) -> Data {
        Data(
            """
            Grid range: GeneralGridEnvelope[0..2, 0..1]
            Grid to world: PARAM_MT["Affine",
              PARAMETER["elt_0_0", 1.0],
              PARAMETER["elt_0_2", 10.0],
              PARAMETER["elt_1_1", -1.0],
              PARAMETER["elt_1_2", 51.0]]
            Contents:
            Band 0:
            \(values)
            """.utf8)
    }

    @Test("The request asks for a text grid of a latitude/longitude box")
    func url() throws {
        let url = try WCSGrid.url(settings, south: 51.47295, west: 0.01085, north: 51.4731, east: 0.01105)
        let items = (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map {
            "\($0.name)=\($0.value ?? "")"
        }

        #expect(url.path() == "/geoservices/datasets/13787b9a-26a4-4775-8523-806d13af58fc/wcs")
        #expect(items.contains("request=GetCoverage") && items.contains("format=text/plain"))
        #expect(items.contains("subset=Lat(51.4729500,51.4731000)"))
        #expect(items.contains("subset=Long(0.0108500,0.0110500)"))
    }

    @Test("The recorded window decodes to a 14 × 17 grid of cell centres, north row first")
    func recordedGrid() throws {
        let grid = try WCSGrid.grid(from: Data(Self.blueStart.utf8))

        #expect(grid.columns == 14 && grid.rows == 17)
        #expect(abs(grid.originLongitude - 0.0108461690) < 1e-9)
        #expect(abs(grid.originLatitude - 51.4730949614) < 1e-9)
        #expect(grid.values.first == 39.806 && grid.values.last == 39.569)
    }

    @Test("The Blue start node reads 39.72 m, as the Environment Agency's point service gives")
    func recordedReading() throws {
        let start = Coordinate(latitude: 51.4730338, longitude: 0.0109583)
        let outside = Coordinate(latitude: 51.4740, longitude: 0.0109583)

        #expect(
            try WCSGrid.readings(from: Data(Self.blueStart.utf8), for: [start, outside], settings) == [
                ElevationReading(elevationMeters: 39.724, source: "ea-dtm-2022"),
                ElevationReading(elevationMeters: nil, source: "no data"),
            ])
    }

    @Test("Values interpolate between cell centres; next to missing cells the nearest cell is used")
    func interpolation() throws {
        let full = try WCSGrid.grid(from: Self.synthetic("1 2 3\n5 6 7"))
        let gap = try WCSGrid.grid(from: Self.synthetic("1 2 0\n5 6 -3.4028235E38"))

        #expect(full.elevation(at: Coordinate(latitude: 50.5, longitude: 10.5)) == 3.5)
        #expect(full.elevation(at: Coordinate(latitude: 51, longitude: 12)) == 3)
        #expect(gap.values == [1, 2, nil, 5, 6, nil])
        #expect(gap.elevation(at: Coordinate(latitude: 50.9, longitude: 11.4)) == 2)
        #expect(gap.elevation(at: Coordinate(latitude: 50.9, longitude: 11.6)) == nil)
    }

    @Test("A response that isn't a grid, or whose values don't fill it, is an error")
    func malformed() {
        let failure = Data(#"{"message":"Internal server error","statusCode":500,"code":"internal_error"}"#.utf8)

        #expect(throws: PipelineError.self) { try WCSGrid.grid(from: failure) }
        #expect(throws: PipelineError.self) { try WCSGrid.grid(from: Self.synthetic("1 2 3\n5 6")) }
    }

    @Test("Points split into runs that each fit the window size")
    func windows() {
        // 10 m apart heading north: 0.0000899° of latitude.
        let line = (0..<60).map { Coordinate(latitude: 51.5 + Double($0) * 0.0000899, longitude: -0.1) }

        #expect(WCSGrid.windows(line, maximumMeters: 250) == [0..<26, 26..<52, 52..<60])
        #expect(WCSGrid.windows([], maximumMeters: 250).isEmpty)
    }
}
