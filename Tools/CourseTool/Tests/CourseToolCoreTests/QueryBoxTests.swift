import Foundation
import Testing

@testable import CourseToolCore

@Suite("Query boxes along a line")
struct QueryBoxTests {
    /// 2.95 km due north from (51.5, -0.1), as two points.
    let line = [
        Coordinate(latitude: 51.5, longitude: -0.1), Coordinate(latitude: 51.5 + 2950 / 111_195, longitude: -0.1),
    ]

    @Test("A long segment is cut into padded boxes no more than the limit across, sharing their ends")
    func northward() {
        let boxes = QueryBox.covering(line, padMeters: 100, maximumMeters: 1000)
        let pad = 100 / 111_195.0

        #expect(boxes.count == 3)
        #expect(abs(boxes[0].south - (51.5 - pad)) < 1e-9)
        #expect(abs(boxes[2].north - (line[1].latitude + pad)) < 1e-9)
        for (a, b) in zip(boxes, boxes.dropFirst()) {
            #expect(abs((a.north - pad) - (b.south + pad)) < 1e-9)
        }
        for box in boxes {
            #expect((box.north - box.south - 2 * pad) * 111_195 <= 1000 + 1e-6)
        }
    }

    @Test("Every point of the line lies inside some box, at least the padding from its edges")
    func coverage() {
        let zigzag = (0..<40).map { k in
            Coordinate(latitude: 51.5 + Double(k) * 0.0009, longitude: -0.1 + (k % 2 == 0 ? 0 : 0.003))
        }
        let boxes = QueryBox.covering(zigzag, padMeters: 50, maximumMeters: 400)
        let padLatitude = 50 / 111_195.0
        for (a, b) in zip(zigzag, zigzag.dropFirst()) {
            for t in stride(from: 0.0, through: 1, by: 0.1) {
                let p = Coordinate(
                    latitude: a.latitude + (b.latitude - a.latitude) * t,
                    longitude: a.longitude + (b.longitude - a.longitude) * t)
                #expect(
                    boxes.contains {
                        p.latitude >= $0.south + padLatitude - 1e-9 && p.latitude <= $0.north - padLatitude + 1e-9
                            && p.longitude >= $0.west && p.longitude <= $0.east
                    })
            }
        }
    }

    @Test("Overpass takes south, west, north, east")
    func overpassOrder() {
        #expect(QueryBox(south: 1, west: 2, north: 3, east: 4).overpass == "1.000000,2.000000,3.000000,4.000000")
        #expect(QueryBox.covering([], padMeters: 10, maximumMeters: 100).isEmpty)
    }
}
