import Foundation
import Testing

@testable import CourseToolCore

@Suite("Geoscience Australia 5 m DEM")
struct GADemTests {
    /// A recorded `identify` response (2026-10-16) for the Sydney start, the Harbour Bridge mid-span (water under the
    /// deck), the finish, and a point in the Tasman Sea. Results are reordered to show matching doesn't rely on order.
    let response = Data(
        """
        {"results":[
        {"layerId":0,"layerName":"DEM_LiDAR_5m_2025","displayFieldName":"","attributes":{"Stretch.Pixel Value":"3.550477"},"geometryType":"esriGeometryPoint","geometry":{"x":151.21416856947414,"y":-33.858270683632959,"spatialReference":{"wkid":4326,"latestWkid":4326}}},
        {"layerId":0,"layerName":"DEM_LiDAR_5m_2025","displayFieldName":"","attributes":{"Stretch.Pixel Value":"NoData"},"geometryType":"esriGeometryPoint","geometry":{"x":151.39999460166518,"y":-33.900012665914289,"spatialReference":{"wkid":4326,"latestWkid":4326}}},
        {"layerId":0,"layerName":"DEM_LiDAR_5m_2025","displayFieldName":"","attributes":{"Stretch.Pixel Value":"85.833267"},"geometryType":"esriGeometryPoint","geometry":{"x":151.20799856523161,"y":-33.833216684384752,"spatialReference":{"wkid":4326,"latestWkid":4326}}},
        {"layerId":0,"layerName":"DEM_LiDAR_5m_2025","displayFieldName":"","attributes":{"Stretch.Pixel Value":"0.146445"},"geometryType":"esriGeometryPoint","geometry":{"x":151.21085556818784,"y":-33.852213683984836,"spatialReference":{"wkid":4326,"latestWkid":4326}}}
        ]}
        """.utf8)

    @Test("Each point takes the pixel containing it, labelled by whether it is water")
    func decodes() throws {
        let points = [
            Coordinate(latitude: -33.833204, longitude: 151.208004),
            Coordinate(latitude: -33.852201, longitude: 151.210861),
            Coordinate(latitude: -33.858258, longitude: 151.214174),
            Coordinate(latitude: -33.900000, longitude: 151.400000),
        ]

        let readings = try GADem.readings(from: response, for: points)

        #expect(readings[0] == ElevationReading(elevationMeters: 85.833, source: "ga5m"))
        #expect(readings[1] == ElevationReading(elevationMeters: 0.146, source: "ga5m-water"))
        #expect(readings[2] == ElevationReading(elevationMeters: 3.55, source: "ga5m"))
        #expect(readings[3] == ElevationReading(elevationMeters: nil, source: "no data"))
    }

    @Test("A point with no pixel in the response is left for another request")
    func missing() throws {
        let readings = try GADem.readings(
            from: response, for: [Coordinate(latitude: -33.8700, longitude: 151.2000)])

        #expect(readings == [nil])
    }

    @Test("A response without results is an error")
    func malformed() {
        #expect(throws: PipelineError.self) {
            try GADem.readings(from: Data(#"{"error":{"code":400}}"#.utf8), for: [])
        }
    }
}
