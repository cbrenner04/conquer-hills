import Foundation

/// Copernicus GLO-30 elevation (`copernicus`): the European Space Agency's global 30 m surface model, published by
/// AWS as cloud-optimised GeoTIFFs, one file per 1° cell.
///
/// Each file is 3600 × 3600 float32 pixels in 1024 × 1024 internal tiles, DEFLATE-compressed with the floating-point
/// predictor. A provider reads the file's header (the first 64 KB), works out which internal tiles the points fall in,
/// fetches only those with range requests, and samples them here. The files are `PixelIsPoint`: the tie point is the
/// centre of the first pixel, not its corner (reading it as a corner would shift every sample by half a pixel,
/// about 15 m).
public enum CopernicusDEM {
    /// The bytes to fetch first: the header and tile index of every GLO-30 file fit in them.
    public static let headerBytes = 65_536
    /// Values at or below this are no data.
    static let noDataBelow: Float = -1000

    /// The file covering `point`'s 1° cell, e.g. `…/Copernicus_DSM_COG_10_N40_00_E117_00_DEM.tif`.
    public static func fileURL(for point: Coordinate) -> URL {
        let lat = Int(point.latitude.rounded(.down))
        let lon = Int(point.longitude.rounded(.down))
        let name = String(
            format: "Copernicus_DSM_COG_10_%@%02d_00_%@%03d_00_DEM", lat < 0 ? "S" : "N", abs(lat), lon < 0 ? "W" : "E",
            abs(lon))
        return URL(string: "https://copernicus-dem-30m.s3.amazonaws.com/\(name)/\(name).tif")!
    }

    /// What a provider needs from a file's header.
    public struct Layout: Equatable, Sendable {
        public var width: Int
        public var height: Int
        public var tileWidth: Int
        public var tileHeight: Int
        public var tileOffsets: [Int]
        public var tileByteCounts: [Int]
        /// The longitude and latitude of the first pixel's centre, and degrees per pixel.
        public var originLongitude: Double
        public var originLatitude: Double
        public var pixelWidth: Double
        public var pixelHeight: Double

        /// The fractional pixel position of `point` (pixel centres at whole numbers).
        public func pixel(_ point: Coordinate) -> (x: Double, y: Double) {
            ((point.longitude - originLongitude) / pixelWidth, (originLatitude - point.latitude) / pixelHeight)
        }

        /// The internal tile holding pixel (`x`, `y`), or nil outside the image.
        public func tile(x: Int, y: Int) -> Int? {
            guard (0..<width).contains(x), (0..<height).contains(y) else { return nil }
            return (y / tileHeight) * ((width + tileWidth - 1) / tileWidth) + x / tileWidth
        }

        /// The internal tiles bilinear sampling at `point` reads.
        public func tiles(for point: Coordinate) -> Set<Int> {
            let (x, y) = pixel(point)
            let x0 = Int(x.rounded(.down))
            let y0 = Int(y.rounded(.down))
            return Set([(x0, y0), (x0 + 1, y0), (x0, y0 + 1), (x0 + 1, y0 + 1)].compactMap { tile(x: $0.0, y: $0.1) })
        }

        /// The elevation at `point`, bilinear between the four pixel centres around it, from `tiles` (decoded,
        /// keyed by index); nil if a pixel is missing or has no data.
        public func elevation(at point: Coordinate, tiles: [Int: [Float]]) -> Double? {
            let (x, y) = pixel(point)
            let x0 = Int(x.rounded(.down))
            let y0 = Int(y.rounded(.down))
            func value(_ px: Int, _ py: Int) -> Double? {
                guard let index = tile(x: px, y: py), let pixels = tiles[index] else { return nil }
                let v = pixels[(py % tileHeight) * tileWidth + px % tileWidth]
                return v <= noDataBelow ? nil : Double(v)
            }
            guard let a = value(x0, y0), let b = value(x0 + 1, y0), let c = value(x0, y0 + 1),
                let d = value(x0 + 1, y0 + 1)
            else { return nil }
            let fx = x - Double(x0)
            let fy = y - Double(y0)
            return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy
        }
    }

    /// Reads the layout from a file's first bytes (a little-endian classic TIFF, as GLO-30 files are).
    public static func layout(fromHeader data: Data) throws -> Layout {
        let bytes = [UInt8](data)
        func fail(_ why: String) -> PipelineError { PipelineError("unexpected Copernicus GeoTIFF header: \(why)") }
        guard bytes.count >= 8, bytes[0] == 0x49, bytes[1] == 0x49, u16(bytes, 2) == 42 else {
            throw fail("not a little-endian TIFF")
        }
        let ifd = Int(u32(bytes, 4))
        guard ifd + 2 <= bytes.count else { throw fail("directory beyond the header") }
        var tags: [Int: [Double]] = [:]
        let typeSizes: [Int: Int] = [1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 11: 4, 12: 8, 16: 8]
        for entry in 0..<Int(u16(bytes, ifd)) {
            let at = ifd + 2 + 12 * entry
            guard at + 12 <= bytes.count else { throw fail("truncated directory") }
            let tag = Int(u16(bytes, at))
            let type = Int(u16(bytes, at + 2))
            let count = Int(u32(bytes, at + 4))
            guard let size = typeSizes[type] else { continue }
            let start = size * count <= 4 ? at + 8 : Int(u32(bytes, at + 8))
            guard start + size * count <= bytes.count else { continue }  // values we don't need, beyond the header
            tags[tag] = (0..<count).map { i -> Double in
                let o = start + i * size
                switch type {
                case 3: return Double(u16(bytes, o))
                case 4: return Double(u32(bytes, o))
                case 16: return Double(u64(bytes, o))
                case 11: return Double(Float(bitPattern: u32(bytes, o)))
                case 12: return Double(bitPattern: u64(bytes, o))
                default: return Double(bytes[o])
                }
            }
        }
        func one(_ tag: Int) throws -> Int {
            guard let v = tags[tag]?.first else { throw fail("missing tag \(tag)") }
            return Int(v)
        }
        guard try one(259) == 8 else { throw fail("compression is not DEFLATE") }
        guard try one(258) == 32, try one(339) == 3 else { throw fail("pixels are not float32") }
        guard try one(317) == 3 else { throw fail("not the floating-point predictor") }
        guard let scale = tags[33550], scale.count >= 2, let tie = tags[33922], tie.count >= 6,
            let offsets = tags[324], let counts = tags[325]
        else { throw fail("missing georeferencing or tile index") }
        // GeoKey 1025 (raster type): 1 = PixelIsArea (tie point at the pixel's corner), 2 = PixelIsPoint (centre).
        var pixelIsPoint = false
        if let keys = tags[34735] {
            for k in stride(from: 4, to: keys.count - 3, by: 4) where Int(keys[k]) == 1025 {
                pixelIsPoint = Int(keys[k + 3]) == 2
            }
        }
        let half = pixelIsPoint ? 0 : 0.5
        return Layout(
            width: try one(256), height: try one(257), tileWidth: try one(322), tileHeight: try one(323),
            tileOffsets: offsets.map { Int($0) }, tileByteCounts: counts.map { Int($0) },
            originLongitude: tie[3] + half * scale[0], originLatitude: tie[4] - half * scale[1],
            pixelWidth: scale[0], pixelHeight: scale[1])
    }

    /// Decodes one internal tile: zlib-wrapped DEFLATE, then the floating-point predictor (horizontal byte
    /// differencing over each row, whose bytes are grouped most significant first).
    public static func pixels(fromTile data: Data, layout: Layout) throws -> [Float] {
        let width = layout.tileWidth
        let rowBytes = width * 4
        guard data.count > 2,
            let inflated = try? (data.dropFirst(2) as NSData).decompressed(using: .zlib) as Data,
            inflated.count == rowBytes * layout.tileHeight
        else { throw PipelineError("could not decompress a Copernicus tile") }
        var bytes = [UInt8](inflated)
        var pixels = [Float](repeating: 0, count: width * layout.tileHeight)
        for row in 0..<layout.tileHeight {
            let base = row * rowBytes
            for i in 1..<rowBytes { bytes[base + i] = bytes[base + i] &+ bytes[base + i - 1] }
            for x in 0..<width {
                let bits =
                    UInt32(bytes[base + x]) << 24 | UInt32(bytes[base + width + x]) << 16
                    | UInt32(bytes[base + 2 * width + x]) << 8 | UInt32(bytes[base + 3 * width + x])
                pixels[row * width + x] = Float(bitPattern: bits)
            }
        }
        return pixels
    }

    private static func u16(_ b: [UInt8], _ o: Int) -> UInt16 { UInt16(b[o]) | UInt16(b[o + 1]) << 8 }
    private static func u32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
    }
    private static func u64(_ b: [UInt8], _ o: Int) -> UInt64 { UInt64(u32(b, o)) | UInt64(u32(b, o + 4)) << 32 }
}
