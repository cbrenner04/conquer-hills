import Foundation

/// The files in `CourseData/<id>/`.
public struct CourseDataFiles: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public var config: URL { directory.appending(path: "config.json") }
    public var waypoints: URL { directory.appending(path: "waypoints.geojson") }
    public var route: URL { directory.appending(path: "route.json") }
    public var structures: URL { directory.appending(path: "osm-structures.json") }
    public var elevationSamples: URL { directory.appending(path: "elevation-samples.json") }
}
