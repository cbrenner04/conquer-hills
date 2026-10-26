import Foundation

/// Decodes an ArcGIS ImageServer `getSamples` response (`usgs3dep`, `imageServer`).
///
/// Each sample carries the index of the point it answers (`locationId`) and its value as a string. Values are
/// multiplied by `zFactor` to give metres (a service in US survey feet uses 1200/3937) and rounded to millimetres.
/// The source label is `label` if given, else the sample's `Name` attribute (3DEP's project name).
public enum ImageServerSamples {
    public static func readings(from data: Data, pointCount: Int, zFactor: Double = 1, label: String? = nil) throws
        -> [Int: ElevationReading]
    {
        struct Response: Decodable {
            struct Sample: Decodable {
                struct Attributes: Decodable {
                    let name: String?
                    enum CodingKeys: String, CodingKey { case name = "Name" }
                }
                let locationId: Int
                let value: String
                let attributes: Attributes?
            }
            let samples: [Sample]?
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data), let samples = response.samples
        else {
            throw PipelineError("unexpected ImageServer response: \(String(decoding: data.prefix(300), as: UTF8.self))")
        }
        var result: [Int: ElevationReading] = [:]
        for sample in samples where sample.locationId >= 0 && sample.locationId < pointCount {
            if let value = Double(sample.value) {
                result[sample.locationId] = ElevationReading(
                    elevationMeters: (value * zFactor * 1000).rounded() / 1000,
                    source: label ?? sample.attributes?.name ?? "unknown")
            } else {
                result[sample.locationId] = ElevationReading(elevationMeters: nil, source: "no data")
            }
        }
        return result
    }
}
