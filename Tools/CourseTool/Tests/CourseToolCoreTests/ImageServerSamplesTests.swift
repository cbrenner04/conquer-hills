import Foundation
import Testing

@testable import CourseToolCore

@Suite("ImageServer samples")
struct ImageServerSamplesTests {
    /// A recorded `getSamples` response (2026-10-16) from the Fairbanks North Star Borough's 2017 lidar service, in
    /// US survey feet: the Ester Dome ridge (mile 13) and mile 7 of the Equinox Marathon.
    static let fairbanks = Data(
        #"{"samples":[{"location":{"x":-148.0535189,"y":64.8798519,"spatialReference":{"wkid":4326,"latestWkid":4326}},"locationId":0,"value":"2315.030517578","rasterId":838,"resolution":1.5,"attributes":{"Name":"bh_FB17_4057","MinPS":0,"MaxPS":4.57200914,"LowPS":0.457200914,"HighPS":0.457200914,"Category":1,"Tag":"Dataset","GroupName":"","ProductName":"","CenterX":-16481082.592618918,"CenterY":9577702.767908936,"ZOrder":null,"Shape.STArea()":4620803.51188381,"Shape.STLength()":8598.423220441764}},{"location":{"x":-147.915,"y":64.8841,"spatialReference":{"wkid":4326,"latestWkid":4326}},"locationId":3,"value":"638.270019531","rasterId":845,"resolution":1.5,"attributes":{"Name":"bh_FB17_4064","MinPS":0,"MaxPS":4.57200914,"LowPS":0.457200914,"HighPS":0.457200914,"Category":1,"Tag":"Dataset","GroupName":"","ProductName":"","CenterX":-16466051.260240417,"CenterY":9578174.947846925,"ZOrder":null,"Shape.STArea()":4621557.645165375,"Shape.STLength()":8599.124858132122}}]}"#
            .utf8)

    /// A recorded 3DEP response (2026-10-16): the Equinox Marathon start, from the 2010 Fairbanks 1/9″ lidar.
    static let usgs = Data(
        #"{"samples":[{"location":{"x":-147.8345364,"y":64.8556189,"spatialReference":{"wkid":4326,"latestWkid":4326}},"locationId":0,"value":"140.987625122","rasterId":9733,"resolution":3.08641987179478e-05,"attributes":{"Name":"ned19_n65x00_w148x00_ak_fairbanks_2010","MinPS":0,"MaxPS":27,"LowPS":3.435786885024356,"HighPS":16,"Category":1,"Tag":"Dataset","GroupName":"","ProductName":"USGS_3DEP","CenterX":-16461372.602056233,"CenterY":9575599.636629606,"ZOrder":null,"Shape_Length":187026.6502000229,"Shape_Area":1829521144.1281142,"Dataset_ID":"usgs","Best":111255,"DEM_Type":1,"Source":"USGS","VerticalDatum":"North American Vertical Datum of 1988 (NAVD 88)","AcquisitionDate":1388534400000,"URL":"https://prd-tnm.s3.amazonaws.com/StagedProducts/Elevation/19/IMG/ned19_n65x00_w148x00_ak_fairbanks_2010.zip","Metadata":"D:\\USGS_3DEP\\data\\19\\ned19_n65x00_w148x00_ak_fairbanks_2010\\ned19_n65x00_w148x00_ak_fairbanks_2010_meta.xml","pubdate":2011,"title":"USGS NED ned19_n65x00_w148x00_ak_fairbanks_2010 1/9 arc-second 2011 15 x 15 minute IMG","Resolution_X":"0.00001","Resolution_Y":1e-05,"Cdate":null,"StartDate":2011,"EndDate":"2014"}}]}"#
            .utf8)

    @Test("Values in US survey feet become metres, with a fixed label")
    func feet() throws {
        let readings = try ImageServerSamples.readings(
            from: Self.fairbanks, pointCount: 4, zFactor: 1200.0 / 3937, label: "fnsb-lidar-2017")

        #expect(readings.keys.sorted() == [0, 3])
        #expect(readings[0] == ElevationReading(elevationMeters: 705.623, source: "fnsb-lidar-2017"))
        #expect(readings[3] == ElevationReading(elevationMeters: 194.545, source: "fnsb-lidar-2017"))
    }

    @Test("3DEP values are metres, labelled with the dataset's name")
    func usgs3dep() throws {
        let readings = try ImageServerSamples.readings(from: Self.usgs, pointCount: 1)

        #expect(
            readings[0] == ElevationReading(elevationMeters: 140.988, source: "ned19_n65x00_w148x00_ak_fairbanks_2010"))
    }

    @Test("NoData is no data, points outside the request are ignored, and an error response throws")
    func edges() throws {
        let data = Data(#"{"samples":[{"locationId":0,"value":"NoData"},{"locationId":5,"value":"1.0"}]}"#.utf8)
        let error = Data(#"{"error":{"code":503,"message":"User couldn't access this resource"}}"#.utf8)

        #expect(
            try ImageServerSamples.readings(from: data, pointCount: 2) == [
                0: ElevationReading(elevationMeters: nil, source: "no data")
            ])
        #expect(throws: PipelineError.self) { try ImageServerSamples.readings(from: error, pointCount: 1) }
    }
}
