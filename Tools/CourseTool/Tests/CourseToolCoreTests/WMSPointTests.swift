import Foundation
import Testing

@testable import CourseToolCore

@Suite("WMS point elevations")
struct WMSPointTests {
    /// The City of Cape Town's lidar terrain model, as configured for Cape Town.
    let capeTown = CourseConfig.WMSPointSettings(
        url: "https://cityimg.capetown.gov.za/erdas-iws/ogc/wms/GeoSpatial%20Datasets", layer: "Elevation_DTM_2m",
        valuePath: "layers.0.raw.bands.0.value", maskPath: "layers.0.raw.bands.1.value",
        labelPath: "layers.0.info.name", label: nil)

    @Test("The request queries the centre pixel of a small box around the point, latitude first")
    func url() throws {
        let url = try WMSPoint.url(capeTown, at: Coordinate(latitude: -33.93174, longitude: 18.4404))
        let items = Dictionary(
            uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map {
                ($0.name, $0.value ?? "")
            })

        #expect(url.path() == "/erdas-iws/ogc/wms/GeoSpatial%20Datasets")
        #expect(items["request"] == "GetFeatureInfo")
        #expect(items["query_layers"] == "Elevation_DTM_2m")
        #expect(items["bbox"] == "-33.9317600,18.4403800,-33.9317200,18.4404200")
        #expect(items["width"] == "3" && items["i"] == "1" && items["j"] == "1")
    }

    /// Recorded responses (2026-10-16) for the N2 off-ramp at Searle St, the sea off Green Point (masked), and a
    /// point outside the survey.
    @Test("Cape Town: elevation and source file from the response; masked and missing values are no data")
    func capeTownResponses() throws {
        let onRoute = Data(
            #"{"layers":[{"name":"Elevation_DTM_2m","rgb":{"red":183,"green":183,"blue":183},"raw":{"bands":[{"index":0,"value":35.7904},{"index":1,"value":255}]},"point":{"x":18.4403933333333,"y":-33.9317333333333},"info":{"name":"LiDAR2025_2m_DTM_v1.tif","timestamp":1757322720000}}]}"#
                .utf8)
        let sea = Data(
            #"{"layers":[{"name":"Elevation_DTM_2m","rgb":{"red":255,"green":255,"blue":255},"raw":{"bands":[{"index":0,"value":0},{"index":1,"value":0}]},"point":{"x":18.3799933333333,"y":-33.8999933333333},"info":{"name":"LiDAR2025_2m_DTM_v1.tif","timestamp":1757322720000}}]}"#
                .utf8)
        let outside = Data(#"{"layers":[{"name":"Elevation_DTM_2m","rgb":{"red":255,"green":255,"blue":255}}]}"#.utf8)

        #expect(
            try WMSPoint.reading(from: onRoute, capeTown)
                == ElevationReading(elevationMeters: 35.79, source: "LiDAR2025_2m_DTM_v1.tif"))
        #expect(try WMSPoint.reading(from: sea, capeTown) == ElevationReading(elevationMeters: nil, source: "no data"))
        #expect(
            try WMSPoint.reading(from: outside, capeTown) == ElevationReading(elevationMeters: nil, source: "no data"))
    }

    @Test("A value given as a string, with a fixed label, reads as a number")
    func stringValue() throws {
        let settings = CourseConfig.WMSPointSettings(
            url: "https://example.org/wms", layer: "dgm", valuePath: "features.0.properties.height", maskPath: nil,
            labelPath: nil, label: "dgm1")
        let data = Data(#"{"type":"FeatureCollection","features":[{"properties":{"height":"33.53"}}]}"#.utf8)

        #expect(try WMSPoint.reading(from: data, settings) == ElevationReading(elevationMeters: 33.53, source: "dgm1"))
    }

    @Test("A response that isn't JSON is an error")
    func malformed() {
        #expect(throws: PipelineError.self) {
            try WMSPoint.reading(from: Data("<ServiceExceptionReport/>".utf8), capeTown)
        }
    }
}
