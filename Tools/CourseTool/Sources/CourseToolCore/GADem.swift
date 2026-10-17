import Foundation

/// Decodes Geoscience Australia's national 5 m LiDAR DEM (`DEM_LiDAR_5m_2025` MapServer) `identify` responses.
///
/// The service returns one result per point it hits, each with the containing pixel's centre and value, in no
/// promised order, so each requested point takes the result whose pixel centre is nearest, if that centre is within
/// half a pixel diagonal. The service has no per-sample source label: samples are labelled `ga5m`, or `ga5m-water`
/// where the value is below `waterBelowMeters` (bridge spans read the water under them).
public enum GADem {
    public static let label = "ga5m"
    public static let waterLabel = "ga5m-water"
    /// Below this, a reading is water: the course's real low points are about 2.2 m.
    public static let waterBelowMeters = 1.0
    /// Half the diagonal of a 5 m pixel, plus a little for coordinate rounding.
    static let matchRadiusMeters = 4.0

    /// One reading per point, nil where the response has no pixel for it (ask again).
    public static func readings(from data: Data, for points: [Coordinate]) throws -> [ElevationReading?] {
        struct Response: Decodable {
            struct Result: Decodable {
                struct Geometry: Decodable {
                    let x: Double
                    let y: Double
                }
                let attributes: [String: String]
                let geometry: Geometry?
            }
            let results: [Result]?
        }
        guard let results = try JSONDecoder().decode(Response.self, from: data).results else {
            throw PipelineError("unexpected GA response: \(String(decoding: data.prefix(300), as: UTF8.self))")
        }
        let projection = Geo.Projection(fitting: points)
        let pixels: [(point: Geo.Point, value: String)] = results.compactMap { result in
            guard let g = result.geometry, let value = result.attributes["Stretch.Pixel Value"] else { return nil }
            return (projection.point(Coordinate(latitude: g.y, longitude: g.x)), value)
        }
        return points.map { coordinate in
            let p = projection.point(coordinate)
            guard let nearest = pixels.min(by: { $0.point.distance(to: p) < $1.point.distance(to: p) }),
                nearest.point.distance(to: p) <= matchRadiusMeters
            else { return nil }
            guard let value = Double(nearest.value) else {
                return ElevationReading(elevationMeters: nil, source: "no data")
            }
            return ElevationReading(
                elevationMeters: (value * 1000).rounded() / 1000, source: value < waterBelowMeters ? waterLabel : label)
        }
    }
}
