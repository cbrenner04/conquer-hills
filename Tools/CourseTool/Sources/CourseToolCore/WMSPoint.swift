import Foundation

/// Point queries against a raster elevation layer through WMS `GetFeatureInfo` (`wmsPoint`), one point per request.
///
/// Each request asks for a 3×3-pixel image of a small box centred on the point and queries the centre pixel, which is
/// the point itself whatever the image's resolution. Servers shape their JSON differently, so the elevation, an
/// optional mask and the source label are read from paths in `CourseConfig.WMSPointSettings`.
public enum WMSPoint {
    /// Half the side of the requested box, in degrees (about 2 m).
    static let halfBoxDegrees = 0.00002

    public static func url(_ settings: CourseConfig.WMSPointSettings, at point: Coordinate) throws -> URL {
        guard var components = URLComponents(string: settings.url) else {
            throw PipelineError("invalid WMS URL \(settings.url)")
        }
        let d = halfBoxDegrees
        // WMS 1.3.0 takes EPSG:4326 boxes in latitude, longitude order.
        let box = String(
            format: "%.7f,%.7f,%.7f,%.7f", point.latitude - d, point.longitude - d, point.latitude + d,
            point.longitude + d)
        components.queryItems = [
            ("service", "WMS"), ("version", "1.3.0"), ("request", "GetFeatureInfo"), ("layers", settings.layer),
            ("query_layers", settings.layer), ("styles", ""), ("crs", "EPSG:4326"), ("bbox", box), ("width", "3"),
            ("height", "3"), ("i", "1"), ("j", "1"), ("info_format", "application/json"), ("format", "image/png"),
        ].map { URLQueryItem(name: $0.0, value: $0.1) }
        guard let url = components.url else { throw PipelineError("invalid WMS URL \(settings.url)") }
        return url
    }

    public static func reading(from data: Data, _ settings: CourseConfig.WMSPointSettings) throws -> ElevationReading {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            throw PipelineError("unexpected WMS response: \(String(decoding: data.prefix(300), as: UTF8.self))")
        }
        let label = settings.labelPath.flatMap { value(at: $0, in: object) as? String } ?? settings.label ?? "wms"
        if let maskPath = settings.maskPath, number(value(at: maskPath, in: object)) == 0 {
            return ElevationReading(elevationMeters: nil, source: "no data")
        }
        guard let elevation = number(value(at: settings.valuePath, in: object)) else {
            return ElevationReading(elevationMeters: nil, source: "no data")
        }
        return ElevationReading(elevationMeters: (elevation * 1000).rounded() / 1000, source: label)
    }

    static func value(at path: String, in object: Any) -> Any? {
        path.split(separator: ".").reduce(Optional(object)) { current, key in
            if let index = Int(key), let array = current as? [Any] {
                return array.indices.contains(index) ? array[index] : nil
            }
            return (current as? [String: Any])?[String(key)]
        }
    }

    private static func number(_ value: Any?) -> Double? {
        if let string = value as? String { return Double(string) }
        return (value as? NSNumber)?.doubleValue
    }
}
