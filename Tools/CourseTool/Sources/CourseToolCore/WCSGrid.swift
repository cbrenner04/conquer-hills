import Foundation

/// Elevation windows from a WCS 2.0.1 coverage served as a plain-text grid (`wcsGrid`), such as the Environment
/// Agency's 1 m lidar terrain model for England.
///
/// A request asks for a small latitude/longitude box around a run of consecutive samples, at the coverage's own
/// resolution. The server answers with a text header (grid range and the affine transform from cell indices to cell
/// centres) and rows of values from north to south. Each point reads the grid by bilinear interpolation between the
/// four cell centres around it, or the nearest cell where one of them has no data.
public enum WCSGrid {
    /// Padding around the points' bounding box, in degrees of latitude (about 5 m), so every point has cells on all
    /// sides.
    static let paddingDegrees = 0.00005
    /// Values at or below this, and exactly 0, are no data: the Environment Agency fills areas outside its coverage
    /// with 0, and documents -3.4028235E38.
    static let noDataBelow = -1e30

    public struct Grid: Equatable, Sendable {
        /// The longitude and latitude of the centre of the first (north-west) cell.
        public var originLongitude: Double
        public var originLatitude: Double
        /// Degrees per cell; `latitudeStep` is negative (rows run north to south).
        public var longitudeStep: Double
        public var latitudeStep: Double
        public var columns: Int
        public var rows: Int
        /// Row-major, north row first; nil where there is no data.
        public var values: [Double?]

        func value(column: Int, row: Int) -> Double? {
            guard (0..<columns).contains(column), (0..<rows).contains(row) else { return nil }
            return values[row * columns + column]
        }

        /// The elevation at `point`, or nil outside the grid or where there is no data.
        public func elevation(at point: Coordinate) -> Double? {
            let x = (point.longitude - originLongitude) / longitudeStep
            let y = (point.latitude - originLatitude) / latitudeStep
            let column = Int(x.rounded(.down))
            let row = Int(y.rounded(.down))
            let fx = x - Double(column)
            let fy = y - Double(row)
            if let a = value(column: column, row: row), let b = value(column: column + 1, row: row),
                let c = value(column: column, row: row + 1), let d = value(column: column + 1, row: row + 1)
            {
                return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy
            }
            return value(column: Int(x.rounded()), row: Int(y.rounded()))
        }
    }

    /// The box to request for `points`: their bounding box, padded.
    public static func window(for points: [Coordinate]) -> (south: Double, west: Double, north: Double, east: Double) {
        let latitudes = points.map(\.latitude)
        let longitudes = points.map(\.longitude)
        let padLatitude = paddingDegrees
        let padLongitude = paddingDegrees / cos((latitudes.min()! + latitudes.max()!) / 2 * .pi / 180)
        return (
            latitudes.min()! - padLatitude, longitudes.min()! - padLongitude, latitudes.max()! + padLatitude,
            longitudes.max()! + padLongitude
        )
    }

    public static func url(
        _ settings: CourseConfig.WCSGridSettings, south: Double, west: Double, north: Double, east: Double
    ) throws -> URL {
        guard var components = URLComponents(string: settings.url) else {
            throw PipelineError("invalid WCS URL \(settings.url)")
        }
        components.queryItems = [
            ("service", "WCS"), ("version", "2.0.1"), ("request", "GetCoverage"), ("CoverageId", settings.coverageId),
            ("format", "text/plain"), ("subsettingCRS", "http://www.opengis.net/def/crs/EPSG/0/4326"),
            ("subset", String(format: "Lat(%.7f,%.7f)", south, north)),
            ("subset", String(format: "Long(%.7f,%.7f)", west, east)),
        ].map { URLQueryItem(name: $0.0, value: $0.1) }
        guard let url = components.url else { throw PipelineError("invalid WCS URL \(settings.url)") }
        return url
    }

    /// Decodes a plain-text grid response.
    public static func grid(from data: Data) throws -> Grid {
        let text = String(decoding: data, as: UTF8.self)
        func fail() -> PipelineError { PipelineError("unexpected WCS response: \(text.prefix(300))") }
        guard let rangeLine = text.split(separator: "\n").first(where: { $0.hasPrefix("Grid range:") }) else {
            throw fail()
        }
        let bounds = rangeLine.matches(of: /(-?\d+)\.\.(-?\d+)/).map { (Int($0.1)!, Int($0.2)!) }
        guard bounds.count == 2, let contents = text.range(of: "Band 0:") else { throw fail() }
        let (i0, i1) = bounds[0]
        let (j0, j1) = bounds[1]
        var affine: [String: Double] = [:]
        for match in text.matches(of: /PARAMETER\["(elt_\d_\d)", (-?[0-9.Ee+-]+)\]/) {
            affine[String(match.1)] = Double(match.2)
        }
        // A missing diagonal element is 1 and a missing off-diagonal one 0 (WKT defaults); only unrotated grids work.
        guard (affine["elt_0_1"] ?? 0) == 0, (affine["elt_1_0"] ?? 0) == 0 else { throw fail() }
        let a = affine["elt_0_0"] ?? 1
        let c = affine["elt_0_2"] ?? 0
        let e = affine["elt_1_1"] ?? 1
        let f = affine["elt_1_2"] ?? 0
        let columns = i1 - i0 + 1
        let rows = j1 - j0 + 1
        let numbers = text[contents.upperBound...].split(whereSeparator: \.isWhitespace).map { Double($0) }
        guard columns > 0, rows > 0, numbers.count == columns * rows, numbers.allSatisfy({ $0 != nil }) else {
            throw fail()
        }
        // The transform maps cell indices (i, j), counted from the grid range's start, to cell centres.
        return Grid(
            originLongitude: a * Double(i0) + c, originLatitude: e * Double(j0) + f, longitudeStep: a,
            latitudeStep: e, columns: columns, rows: rows,
            values: numbers.map { $0! <= noDataBelow || $0! == 0 ? nil : $0! })
    }

    /// One reading per point from a grid response, rounded to millimetres and labelled `settings.label`.
    public static func readings(from data: Data, for points: [Coordinate], _ settings: CourseConfig.WCSGridSettings)
        throws -> [ElevationReading]
    {
        let grid = try grid(from: data)
        return points.map { point in
            guard let elevation = grid.elevation(at: point) else {
                return ElevationReading(elevationMeters: nil, source: "no data")
            }
            return ElevationReading(elevationMeters: (elevation * 1000).rounded() / 1000, source: settings.label)
        }
    }

    /// Splits points into runs whose bounding box stays within `maximumMeters` on each side, so each run is one
    /// small request.
    public static func windows(_ points: [Coordinate], maximumMeters: Double) -> [Range<Int>] {
        var runs: [Range<Int>] = []
        var start = 0
        var box: (south: Double, west: Double, north: Double, east: Double)?
        for (index, point) in points.enumerated() {
            let grown =
                box.map {
                    (
                        min($0.south, point.latitude), min($0.west, point.longitude), max($0.north, point.latitude),
                        max($0.east, point.longitude)
                    )
                } ?? (point.latitude, point.longitude, point.latitude, point.longitude)
            let height = (grown.2 - grown.0) * 111_195
            let width = (grown.3 - grown.1) * 111_195 * cos(point.latitude * .pi / 180)
            if box != nil, height > maximumMeters || width > maximumMeters {
                runs.append(start..<index)
                start = index
                box = (point.latitude, point.longitude, point.latitude, point.longitude)
            } else {
                box = grown
            }
        }
        if start < points.count { runs.append(start..<points.count) }
        return runs
    }
}
