import CourseKit
import CourseToolCore
import Foundation

let usage = """
    usage: course-tool <command> <course-id> [options]

    commands:
      route      route source → route.json, and refresh osm-structures.json      (network)
      elevation  fill or resume elevation-samples.json                             (network)
      build      build the course file and the review report                       (offline)
      check      rebuild in memory; fail if the bundled course file differs or a check fails (offline)

    options:
      --data <dir>      course data directory      (default: CourseData)
      --courses <dir>   bundled courses directory  (default: App/Resources/Courses)
      --report <dir>    review report directory    (default: .scratch/reports)
    """

var arguments = Array(CommandLine.arguments.dropFirst())
@MainActor func option(_ name: String, default value: String) -> String {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return value }
    let result = arguments[index + 1]
    arguments.removeSubrange(index...(index + 1))
    return result
}
let dataRoot = URL(filePath: option("--data", default: "CourseData"))
let coursesDirectory = URL(filePath: option("--courses", default: "App/Resources/Courses"))
let reportDirectory = URL(filePath: option("--report", default: ".scratch/reports"))
guard arguments.count == 2 else {
    log(usage)
    exit(2)
}
let command = arguments[0]
let courseID = arguments[1]
let courseDirectory = dataRoot.appending(path: courseID)
let files = CourseDataFiles(directory: courseDirectory)

do {
    let config = try PipelineJSON.decode(CourseConfig.self, from: files.config)
    guard config.id == courseID else { throw PipelineError("config id \(config.id) does not match \(courseID)") }

    switch command {
    case "route":
        try await route(config: config)
    case "elevation":
        try await fetchElevation(config: config)
    case "build", "check":
        let inputs = try BuildInputs.load(from: files, config: config)
        let result = try CourseBuilder.build(inputs)
        for line in result.summaryLines { log(line) }
        let courseURL = coursesDirectory.appending(path: config.id + CourseLoader.fileSuffix)
        if command == "build" {
            try result.courseData.write(to: courseURL, options: .atomic)
            try FileManager.default.createDirectory(at: reportDirectory, withIntermediateDirectories: true)
            let reportURL = reportDirectory.appending(path: config.id + ".html")
            try Data(ReviewReport.html(for: result, inputs: inputs).utf8).write(to: reportURL, options: .atomic)
            log("wrote \(courseURL.path)\nwrote \(reportURL.path)")
        } else {
            let bundled = try? Data(contentsOf: courseURL)
            guard bundled == result.courseData else {
                throw PipelineError("\(courseURL.path) is out of date: run `make course-build ID=\(config.id)`")
            }
            log("\(config.id): bundled course file matches its inputs")
        }
        guard result.allChecksPass else { throw PipelineError("\(config.id): checks failed (see above)") }
    default:
        log(usage)
        exit(2)
    }
} catch {
    log("error: \(error)")
    exit(1)
}

@MainActor func route(config: CourseConfig) async throws {
    let line: [Coordinate]
    var properties = ["license": "ODbL-1.0", "attribution": "© OpenStreetMap contributors"]
    switch config.route {
    case .waypoints(let routerBaseURL):
        let waypoints = try GeoJSON.readWaypoints(Data(contentsOf: files.waypoints))
        log("routing \(waypoints.count) waypoints with \(routerBaseURL)")
        line = try await OSRMRouter.route(through: waypoints, baseURL: routerBaseURL)
        properties["router"] = routerBaseURL
    case .osmRelation(let id, let start):
        log("importing OSM relation \(id)")
        let (relationLine, timestamp) = try await Overpass.relationRoute(id: id, start: start)
        line = relationLine
        properties["osmRelation"] = String(id)
        properties["osmTimestamp"] = timestamp
    }
    // The route is rounded once, here, by encoding; everything downstream uses the stored (decoded) points.
    let routeFile = RouteFile(line: line, properties: properties)
    try PipelineJSON.write(routeFile, to: files.route)
    let route = routeFile.line
    log("wrote \(files.route.path) (\(route.count) points)")

    log("querying OSM bridges, tunnels and covered ways along the route")
    let (ways, timestamp) = try await Overpass.structures(along: route, bufferMeters: config.structures.bufferMeters)
    let structures = structuresFile(config: config, route: route, ways: ways, timestamp: timestamp)
    try PipelineJSON.write(structures, to: files.structures)
    log(
        "wrote \(files.structures.path) (\(structures.spans.count) spans from \(ways.count) ways, OSM as of \(timestamp))"
    )
}

func structuresFile(config: CourseConfig, route: [Coordinate], ways: [StructureSpans.Way], timestamp: String)
    -> StructuresFile
{
    let p = config.processing
    let positions = RouteSampling.positions(
        route: route, smoothingMeters: p.routeSmoothingMeters, spacing: p.sampleSpacingMeters)
    return StructuresFile(
        osmTimestamp: timestamp, settings: config.structures,
        routeFingerprint: RouteSampling.fingerprint(
            route: route, smoothingMeters: p.routeSmoothingMeters, spacing: p.sampleSpacingMeters),
        spans: StructureSpans.compute(ways: ways, positions: positions, settings: config.structures))
}

@MainActor func fetchElevation(config: CourseConfig) async throws {
    let provider: any ElevationProvider
    switch config.elevation.provider {
    case "gsi": provider = GSIElevationProvider()
    default:
        throw PipelineError("elevation provider \(config.elevation.provider) is not implemented yet")
    }
    let route = try PipelineJSON.decode(RouteFile.self, from: files.route).line
    let existing = try? PipelineJSON.decode(ElevationSamplesFile.self, from: files.elevationSamples)
    let p = config.processing
    var samples = RouteSampling.prepare(
        existing: existing, route: route, provider: provider.name, smoothingMeters: p.routeSmoothingMeters,
        spacing: p.sampleSpacingMeters)
    let positions = RouteSampling.positions(
        route: route, smoothingMeters: p.routeSmoothingMeters, spacing: p.sampleSpacingMeters)
    let missing = samples.missing
    log("\(samples.count) samples, \(missing.count) to fetch from \(provider.name)")
    var sinceSave = 0
    for batchStart in stride(from: 0, to: missing.count, by: provider.batchSize) {
        let batch = Array(missing[batchStart..<min(batchStart + provider.batchSize, missing.count)])
        let readings = try await provider.elevations(at: batch.map { positions[$0].location })
        for (index, reading) in zip(batch, readings) {
            samples.record(reading.elevationMeters, source: reading.source, at: index)
        }
        sinceSave += batch.count
        if sinceSave >= 25 || batchStart + provider.batchSize >= missing.count {
            if samples.isComplete {
                samples.fetchedOn = ISO8601DateFormatter.string(
                    from: Date(), timeZone: .gmt, formatOptions: [.withFullDate])
            }
            try PipelineJSON.write(samples, to: files.elevationSamples)
            sinceSave = 0
            log("  \(batchStart + batch.count)/\(missing.count)")
        }
    }
    if missing.isEmpty { log("nothing to fetch") }
}
