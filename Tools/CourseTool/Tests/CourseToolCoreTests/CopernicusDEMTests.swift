import Foundation
import Testing

@testable import CourseToolCore

@Suite("Copernicus GLO-30")
struct CopernicusDEMTests {
    /// A 4 × 4 float32 GeoTIFF in one 4 × 4 tile, laid out as GLO-30 files are: DEFLATE (zlib-wrapped) with the
    /// floating-point predictor, georeferenced by a tie point and pixel scale, with a raster-type GeoKey.
    static func geoTIFF(_ values: [Float], pixelIsPoint: Bool = true) -> (header: Data, tile: Data) {
        // Floating-point predictor: per row, bytes grouped most significant first, then differenced.
        var encoded: [UInt8] = []
        for row in 0..<4 {
            let bits = values[row * 4..<row * 4 + 4].map(\.bitPattern)
            var planes: [UInt8] = []
            for shift in [24, 16, 8, 0] { planes += bits.map { UInt8(truncatingIfNeeded: $0 >> UInt32(shift)) } }
            encoded += planes.enumerated().map { i, b in i == 0 ? b : b &- planes[i - 1] }
        }
        let deflated = try! (Data(encoded) as NSData).compressed(using: .zlib) as Data
        let tile = Data([0x78, 0x9C]) + deflated + Data([0, 0, 0, 0])

        var out = Data("II".utf8) + le16(42) + le32(8)
        let doubles = (scale: [0.25, 0.25, 0.0], tie: [0, 0, 0, 10.0, 51.0, 0])
        let geoKeys: [UInt16] = [1, 1, 0, 1, 1025, 0, 1, pixelIsPoint ? 2 : 1]
        let entries: [(tag: UInt16, type: UInt16, values: Data, count: Int)] = [
            (256, 3, le16(4), 1), (257, 3, le16(4), 1), (258, 3, le16(32), 1), (259, 3, le16(8), 1),
            (317, 3, le16(3), 1), (322, 3, le16(4), 1), (323, 3, le16(4), 1), (324, 4, le32(0), 1),
            (325, 4, le32(UInt32(tile.count)), 1), (339, 3, le16(3), 1),
            (33550, 12, doubles.scale.reduce(Data()) { $0 + le64($1.bitPattern) }, 3),
            (33922, 12, doubles.tie.reduce(Data()) { $0 + le64($1.bitPattern) }, 6),
            (34735, 3, geoKeys.reduce(Data()) { $0 + le16($1) }, geoKeys.count),
        ]
        var extra = Data()
        let extraStart = 8 + 2 + entries.count * 12 + 4
        out += le16(UInt16(entries.count))
        for e in entries {
            out += le16(e.tag) + le16(e.type) + le32(UInt32(e.count))
            if e.values.count <= 4 {
                out += e.values + Data(repeating: 0, count: 4 - e.values.count)
            } else {
                out += le32(UInt32(extraStart + extra.count))
                extra += e.values
            }
        }
        return (out + le32(0) + extra, tile)
    }

    static func le16(_ v: UInt16) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8)]) }
    static func le32(_ v: UInt32) -> Data { Data((0..<4).map { UInt8(truncatingIfNeeded: v >> ($0 * 8)) }) }
    static func le64(_ v: UInt64) -> Data { Data((0..<8).map { UInt8(truncatingIfNeeded: v >> ($0 * 8)) }) }

    let values: [Float] = [100, 101, 102, 103, 110, 111, 112, 113, 120, 121, 122, 123, 130, 131, 132, -32767]

    @Test("The header gives the image, tile and georeferencing")
    func header() throws {
        let file = Self.geoTIFF(values)
        let layout = try CopernicusDEM.layout(fromHeader: file.header)

        #expect(layout.width == 4 && layout.tileWidth == 4 && layout.tileOffsets == [0])
        #expect(layout.tileByteCounts == [file.tile.count])
        #expect(layout.originLongitude == 10 && layout.originLatitude == 51)
    }

    @Test("A tile decodes back to its values")
    func decode() throws {
        let file = Self.geoTIFF(values)
        let layout = try CopernicusDEM.layout(fromHeader: file.header)

        #expect(try CopernicusDEM.pixels(fromTile: file.tile, layout: layout) == values)
    }

    @Test("PixelIsPoint puts pixel centres on the tie point; samples are bilinear; no data stays out")
    func sample() throws {
        let file = Self.geoTIFF(values)
        let layout = try CopernicusDEM.layout(fromHeader: file.header)
        let tiles = [0: try CopernicusDEM.pixels(fromTile: file.tile, layout: layout)]

        #expect(layout.elevation(at: Coordinate(latitude: 51, longitude: 10), tiles: tiles) == 100)
        #expect(layout.elevation(at: Coordinate(latitude: 50.875, longitude: 10.125), tiles: tiles) == 105.5)
        #expect(layout.elevation(at: Coordinate(latitude: 50.375, longitude: 10.625), tiles: tiles) == nil)
        #expect(layout.tiles(for: Coordinate(latitude: 50.9, longitude: 10.1)) == [0])
    }

    @Test("PixelIsArea puts the tie point on the first pixel's corner, half a pixel from its centre")
    func pixelIsArea() throws {
        let layout = try CopernicusDEM.layout(fromHeader: Self.geoTIFF(values, pixelIsPoint: false).header)

        #expect(layout.originLongitude == 10.125 && layout.originLatitude == 50.875)
    }

    @Test("Files are named by their 1° cell's south-west corner")
    func fileNames() {
        #expect(
            CopernicusDEM.fileURL(for: Coordinate(latitude: 40.25, longitude: 117.45)).lastPathComponent
                == "Copernicus_DSM_COG_10_N40_00_E117_00_DEM.tif")
        #expect(
            CopernicusDEM.fileURL(for: Coordinate(latitude: -33.4, longitude: -70.6)).lastPathComponent
                == "Copernicus_DSM_COG_10_S34_00_W071_00_DEM.tif")
    }

    @Test("A header that isn't a GLO-30 GeoTIFF is an error")
    func malformed() {
        #expect(throws: PipelineError.self) { try CopernicusDEM.layout(fromHeader: Data("<Error>".utf8)) }
    }
}
