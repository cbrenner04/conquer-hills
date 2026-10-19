import Foundation

/// Latitude/longitude boxes that cover a line, for OSM queries by box.
///
/// Overpass's `around` filter along a line has been seen answering with nothing found while box queries work, and
/// the OSM API only answers boxes, so corridors are downloaded as boxes. Each box covers a stretch of the line no
/// more than `maximumMeters` across, padded by `padMeters` on every side; neighbouring stretches share their end
/// point, so together the boxes cover every point within `padMeters` of the line (and some more, near corners).
public struct QueryBox: Equatable, Sendable {
    public var south: Double
    public var west: Double
    public var north: Double
    public var east: Double

    public init(south: Double, west: Double, north: Double, east: Double) {
        self.south = south
        self.west = west
        self.north = north
        self.east = east
    }

    /// Overpass's box order: south, west, north, east.
    public var overpass: String { String(format: "%.6f,%.6f,%.6f,%.6f", south, west, north, east) }

    public static func covering(_ line: [Coordinate], padMeters: Double, maximumMeters: Double) -> [QueryBox] {
        guard let first = line.first else { return [] }
        // Cut long segments so that every stretch can stay within the size limit.
        var points = [first]
        for (a, b) in zip(line, line.dropFirst()) {
            let pieces = max(1, Int((Geo.distance(a, b) / (maximumMeters / 2)).rounded(.up)))
            for k in 1...pieces {
                let t = Double(k) / Double(pieces)
                points.append(
                    Coordinate(
                        latitude: a.latitude + (b.latitude - a.latitude) * t,
                        longitude: a.longitude + (b.longitude - a.longitude) * t))
            }
        }
        var boxes: [QueryBox] = []
        var stretch = [points[0]]
        func close() {
            let latitudes = stretch.map(\.latitude)
            let longitudes = stretch.map(\.longitude)
            let padLatitude = padMeters / 111_195
            let padLongitude = padLatitude / cos((latitudes.min()! + latitudes.max()!) / 2 * .pi / 180)
            boxes.append(
                QueryBox(
                    south: latitudes.min()! - padLatitude, west: longitudes.min()! - padLongitude,
                    north: latitudes.max()! + padLatitude, east: longitudes.max()! + padLongitude))
        }
        for point in points.dropFirst() {
            let grown = stretch + [point]
            let height = (grown.map(\.latitude).max()! - grown.map(\.latitude).min()!) * 111_195
            let width =
                (grown.map(\.longitude).max()! - grown.map(\.longitude).min()!) * 111_195
                * cos(point.latitude * .pi / 180)
            if stretch.count > 1, height > maximumMeters || width > maximumMeters {
                close()
                stretch = [stretch.last!, point]
            } else {
                stretch = grown
            }
        }
        close()
        return boxes
    }
}
