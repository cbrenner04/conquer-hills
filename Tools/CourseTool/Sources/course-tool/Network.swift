import CourseToolCore
import Foundation

/// Polite HTTP: identifies the tool, retries transient failures with backoff.
enum HTTP {
    static let userAgent = "conquer-hills-course-tool (https://github.com/cbrenner04/conquer-hills)"

    static let retriedStatuses: Set<Int> = [429, 500, 502, 503, 504]

    /// `alsoRetrying` adds statuses a service uses for "slow down" (the Environment Agency's gateway answers 403).
    static func get(_ url: URL, alsoRetrying: Set<Int> = []) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return try await send(request, retrying: retriedStatuses.union(alsoRetrying))
    }

    /// The bytes `range` of `url` (an HTTP range request, answered 206).
    static func get(_ url: URL, bytes range: Range<Int>) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("bytes=\(range.lowerBound)-\(range.upperBound - 1)", forHTTPHeaderField: "Range")
        return try await send(request, retrying: retriedStatuses)
    }

    static func postForm(_ url: URL, fields: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        // URLComponents leaves "+" alone, which form decoding would read as a space.
        request.httpBody = Data(
            (components.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        return try await send(request, retrying: retriedStatuses)
    }

    private static func send(_ request: URLRequest, retrying: Set<Int>, attempts: Int = 5) async throws -> Data {
        // Overpass queries are allowed up to 300 s on the server; the default 60 s would give up on them.
        var request = request
        request.timeoutInterval = 300
        var delay: Duration = .seconds(5)
        for attempt in 1...attempts {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 200 || status == 206 { return data }
                if attempt == attempts || !retrying.contains(status) {
                    throw PipelineError("HTTP \(status) from \(request.url?.host() ?? "?")")
                }
            } catch let error as URLError where attempt < attempts {
                log("  network error (\(error.code.rawValue)); retrying")
            }
            try await Task.sleep(for: delay)
            delay *= 2
        }
        throw PipelineError("unreachable")
    }
}

func log(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

/// Snaps waypoints to OSM roads with an OSRM-compatible router (one request for the whole route).
enum OSRMRouter {
    static func route(through waypoints: [NamedPoint], baseURL: String) async throws -> [Coordinate] {
        let coordinates = waypoints.map { "\($0.location.longitude),\($0.location.latitude)" }.joined(separator: ";")
        guard
            let url = URL(string: "\(baseURL)/route/v1/driving/\(coordinates)?overview=full&geometries=geojson")
        else { throw PipelineError("bad router URL") }
        struct Response: Decodable {
            struct Route: Decodable {
                struct Geometry: Decodable { let coordinates: [[Double]] }
                let geometry: Geometry
                let distance: Double
            }
            let code: String
            let routes: [Route]?
        }
        let response = try JSONDecoder().decode(Response.self, from: try await HTTP.get(url))
        guard response.code == "Ok", let route = response.routes?.first else {
            throw PipelineError("router returned \(response.code)")
        }
        log("  routed \(Int(route.distance)) m through \(waypoints.count) waypoints")
        return route.geometry.coordinates.map { Coordinate(latitude: $0[1], longitude: $0[0]) }
    }
}

/// OpenStreetMap queries through the Overpass API, falling back to a mirror when the main server is busy.
enum Overpass {
    static let endpoints = [
        "https://overpass-api.de/api/interpreter", "https://overpass.private.coffee/api/interpreter",
    ]

    struct Response: Decodable {
        struct OSM3S: Decodable {
            let timestampOSMBase: String
            enum CodingKeys: String, CodingKey { case timestampOSMBase = "timestamp_osm_base" }
        }
        struct Element: Decodable {
            struct LatLon: Decodable {
                let lat: Double
                let lon: Double
            }
            let type: String
            let id: Int
            let lat: Double?
            let lon: Double?
            let nodes: [Int]?
            let tags: [String: String]?
            let geometry: [LatLon]?
            let version: Int?
            let timestamp: String?
        }
        let osm3s: OSM3S
        let elements: [Element]
    }

    static func query(_ ql: String) async throws -> Response {
        var lastError: Error = PipelineError("no Overpass endpoint tried")
        for endpoint in endpoints {
            do {
                let data = try await HTTP.postForm(URL(string: endpoint)!, fields: ["data": ql])
                return try JSONDecoder().decode(Response.self, from: data)
            } catch {
                log("  Overpass \(endpoint) failed: \(error)")
                lastError = error
            }
        }
        throw lastError
    }

    /// Bridges, tunnels and covered ways within `buffer` meters of the route line, with their OSM data timestamp.
    static func structures(along line: [Coordinate], bufferMeters: Double) async throws -> (
        ways: [StructureSpans.Way], timestamp: String
    ) {
        let boxes = QueryBox.covering(line, padMeters: bufferMeters, maximumMeters: 1000)
        let clauses = boxes.map { box in
            """
              way(\(box.overpass))["bridge"]["bridge"!="no"];
              way(\(box.overpass))["tunnel"]["tunnel"!="no"];
              way(\(box.overpass))["covered"="yes"];
            """
        }
        let ql = """
            [out:json][timeout:180];
            (
            \(clauses.joined(separator: "\n"))
            );
            out tags geom;
            """
        let response = try await query(ql)
        let ways = response.elements.filter { $0.type == "way" }.map { element in
            StructureSpans.Way(
                id: element.id, tags: element.tags ?? [:],
                geometry: (element.geometry ?? []).map { Coordinate(latitude: $0.lat, longitude: $0.lon) })
        }
        return (ways, response.osm3s.timestampOSMBase)
    }

    /// The member ways of a route relation, chained into one line, with the relation's version and the OSM data
    /// timestamp so the snapshot can be identified later.
    static func relationRoute(id: Int, start: Coordinate) async throws -> (
        line: [Coordinate], version: Int, edited: String, timestamp: String
    ) {
        let response = try await query(
            "[out:json][timeout:180];relation(\(id));out meta;way(r);out body;>;out skel qt;")
        var nodes: [Int: Coordinate] = [:]
        var ways: [RelationChaining.Way] = []
        var relation: Response.Element?
        for element in response.elements {
            if element.type == "node", let lat = element.lat, let lon = element.lon {
                nodes[element.id] = Coordinate(latitude: lat, longitude: lon)
            } else if element.type == "way", let wayNodes = element.nodes {
                ways.append(.init(id: element.id, nodes: wayNodes))
            } else if element.type == "relation" {
                relation = element
            }
        }
        guard let relation, let version = relation.version else { throw PipelineError("relation \(id) not found") }
        let chained = try RelationChaining.chain(ways: ways, nodeLocations: nodes, start: start)
        log("  relation \(id) v\(version): \(ways.count) ways chained")
        return (
            chained.compactMap { nodes[$0] }, version, relation.timestamp ?? "unknown",
            response.osm3s.timestampOSMBase
        )
    }
}

/// OSM ways and nodes around a course, for `RouteGraph`.
///
/// Asks Overpass (and its mirror) for the ways in a corridor around the waypoints. Overpass is often overloaded; if
/// every endpoint fails, falls back to the OSM API's `map` call over small boxes along the waypoints, paced at one
/// request a second.
enum OSMData {
    struct Corridor {
        var ways: [RouteGraph.Way]
        var nodes: [Int: Coordinate]
        /// Where the data came from, for provenance.
        var source: String
        var timestamp: String
    }

    static func corridor(around waypoints: [Coordinate], settings: CourseConfig.OSMGraphSettings) async throws
        -> Corridor
    {
        do {
            return try await overpass(around: waypoints, settings: settings)
        } catch {
            log("  Overpass unavailable (\(error)); falling back to the OSM API")
            return try await mapBoxes(around: waypoints, settings: settings)
        }
    }

    private static func overpass(around waypoints: [Coordinate], settings: CourseConfig.OSMGraphSettings)
        async throws -> Corridor
    {
        let highways = (settings.highways ?? RouteGraph.defaultHighways).joined(separator: "|")
        let extra =
            settings.includeWays.isEmpty
            ? "" : "way(id:\(settings.includeWays.map(String.init).joined(separator: ",")));"
        let boxes = QueryBox.covering(waypoints, padMeters: settings.corridorMeters, maximumMeters: 1000)
        let clauses = boxes.map { "  way(\($0.overpass))[\"highway\"~\"^(\(highways))$\"];" }
        let response = try await Overpass.query(
            """
            [out:json][timeout:300];
            (
            \(clauses.joined(separator: "\n"))
              \(extra)
            );
            out meta;
            >;
            out skel qt;
            """)
        let (ways, nodes) = graphData(response.elements)
        // A struggling server can answer 200 with nothing found; that is a failure, not a result.
        let included = Set(settings.includeWays)
        guard ways.contains(where: { !included.contains($0.id) }) else {
            throw PipelineError("Overpass found no ways along the waypoints")
        }
        return Corridor(ways: ways, nodes: nodes, source: "Overpass", timestamp: response.osm3s.timestampOSMBase)
    }

    private static func mapBoxes(around waypoints: [Coordinate], settings: CourseConfig.OSMGraphSettings)
        async throws -> Corridor
    {
        // Boxes about 1 km across, padded by the corridor, stay far below the API's area and node limits.
        let boxes = QueryBox.covering(waypoints, padMeters: settings.corridorMeters, maximumMeters: 1000)
        var elements: [Int: Overpass.Response.Element] = [:]
        var nodes: [Int: Overpass.Response.Element] = [:]
        for (number, box) in boxes.enumerated() {
            let url = URL(
                string: String(
                    format: "https://api.openstreetmap.org/api/0.6/map.json?bbox=%.6f,%.6f,%.6f,%.6f", box.west,
                    box.south, box.east, box.north))!
            struct Response: Decodable { let elements: [Overpass.Response.Element] }
            let response = try JSONDecoder().decode(Response.self, from: try await HTTP.get(url))
            for element in response.elements {
                if element.type == "way" { elements[element.id] = element }
                if element.type == "node" { nodes[element.id] = element }
            }
            if (number + 1) % 10 == 0 { log("  OSM API: \(number + 1)/\(boxes.count) boxes") }
            try await Task.sleep(for: .seconds(1))
        }
        for id in settings.includeWays where elements[id] == nil {
            struct Response: Decodable { let elements: [Overpass.Response.Element] }
            let url = URL(string: "https://api.openstreetmap.org/api/0.6/way/\(id)/full.json")!
            for element in try JSONDecoder().decode(Response.self, from: try await HTTP.get(url)).elements {
                if element.type == "way" { elements[element.id] = element }
                if element.type == "node" { nodes[element.id] = element }
            }
            try await Task.sleep(for: .seconds(1))
        }
        let (ways, locations) = graphData(Array(elements.values) + Array(nodes.values))
        let timestamp = ways.compactMap { elements[$0.id]?.timestamp }.max() ?? "unknown"
        return Corridor(
            ways: ways.sorted { $0.id < $1.id }, nodes: locations, source: "OSM API map", timestamp: timestamp)
    }

    private static func graphData(_ elements: [Overpass.Response.Element]) -> ([RouteGraph.Way], [Int: Coordinate]) {
        var ways: [RouteGraph.Way] = []
        var nodes: [Int: Coordinate] = [:]
        for element in elements {
            if element.type == "node", let lat = element.lat, let lon = element.lon {
                nodes[element.id] = Coordinate(latitude: lat, longitude: lon)
            } else if element.type == "way", let wayNodes = element.nodes {
                ways.append(
                    RouteGraph.Way(id: element.id, version: element.version, nodes: wayNodes, tags: element.tags ?? [:])
                )
            }
        }
        return (ways, nodes)
    }
}

/// An ArcGIS ImageServer's batch `getSamples` (decoded by `ImageServerSamples`): the USGS 3D Elevation Program by
/// default (`usgs3dep`), or any other elevation service configured by `elevation.imageServer` (`imageServer`).
///
/// For 3DEP, each point gets the best available DEM (1 m lidar where it exists) and the source label is that dataset's
/// project name, e.g. `MA_CentralEastern_2021_B21`. The service advertises 2,000 points a request but can silently
/// return fewer samples than points, so requests are kept to 500 points and any point left out of a response is
/// asked for again. Requests are spaced a few seconds apart.
struct ImageServerElevationProvider: ElevationProvider {
    let name: String
    let batchSize = 500
    var url = "https://elevation.nationalmap.gov/arcgis/rest/services/3DEPElevation/ImageServer"
    var zFactor = 1.0
    var label: String?

    static let usgs3dep = ImageServerElevationProvider(name: "usgs3dep")

    init(name: String) { self.name = name }

    init(settings: CourseConfig.ImageServerSettings) {
        name = "imageServer"
        url = settings.url
        zFactor = settings.zFactor
        label = settings.label
    }

    func elevations(at points: [Coordinate]) async throws -> [ElevationReading] {
        var readings = [ElevationReading?](repeating: nil, count: points.count)
        for attempt in 1...4 {
            let pending = points.indices.filter { readings[$0] == nil }
            if pending.isEmpty { break }
            if attempt > 1 { log("  ImageServer: asking again for \(pending.count) points left out of the response") }
            let returned = try await samples(at: pending.map { points[$0] })
            for (offset, reading) in returned { readings[pending[offset]] = reading }
            try await Task.sleep(for: .seconds(3))
        }
        guard readings.allSatisfy({ $0 != nil }) else {
            throw PipelineError("the ImageServer kept leaving points out of its responses; try again later")
        }
        return readings.map { $0! }
    }

    /// The samples the service returned, keyed by position in `points`. A sample whose value isn't a number is
    /// recorded as no data; a point missing from the response is left out, so it can be asked for again.
    private func samples(at points: [Coordinate]) async throws -> [Int: ElevationReading] {
        let pointList = points.map { String(format: "[%.7f,%.7f]", $0.longitude, $0.latitude) }.joined(separator: ",")
        let data = try await HTTP.postForm(
            URL(string: url + "/getSamples")!,
            fields: [
                "geometry": "{\"points\":[\(pointList)],\"spatialReference\":{\"wkid\":4326}}",
                "geometryType": "esriGeometryMultipoint", "returnFirstValueOnly": "true",
                "interpolation": "RSP_BilinearInterpolation", "outFields": "Name", "f": "json",
            ])
        return try ImageServerSamples.readings(from: data, pointCount: points.count, zFactor: zFactor, label: label)
    }
}

/// Geoscience Australia's national 5 m LiDAR DEM, through the `DEM_LiDAR_5m_2025` MapServer's `identify` with a
/// multipoint (decoded by `GADem`). Up to 500 points a request, about 17 s each; requests are spaced a second apart,
/// and points left out of a response are asked for again.
struct GADem5mElevationProvider: ElevationProvider {
    let name = "gaDem5m"
    let batchSize = 500

    func elevations(at points: [Coordinate]) async throws -> [ElevationReading] {
        var readings = [ElevationReading?](repeating: nil, count: points.count)
        for attempt in 1...4 {
            let pending = points.indices.filter { readings[$0] == nil }
            if pending.isEmpty { break }
            if attempt > 1 { log("  GA: asking again for \(pending.count) points left out of the response") }
            let batch = pending.map { points[$0] }
            for (offset, reading) in try GADem.readings(from: try await Self.identify(batch), for: batch).enumerated() {
                readings[pending[offset]] = reading
            }
            try await Task.sleep(for: .seconds(1))
        }
        guard readings.allSatisfy({ $0 != nil }) else {
            throw PipelineError("GA kept leaving points out of its responses; try again later")
        }
        return readings.map { $0! }
    }

    private static func identify(_ points: [Coordinate]) async throws -> Data {
        let pointList = points.map { String(format: "[%.7f,%.7f]", $0.longitude, $0.latitude) }.joined(separator: ",")
        let lats = points.map(\.latitude)
        let lons = points.map(\.longitude)
        // `identify` requires a map extent and image size; with zero tolerance they only need to cover the points.
        let extent = String(
            format: "%.6f,%.6f,%.6f,%.6f", lons.min()! - 0.01, lats.min()! - 0.01, lons.max()! + 0.01,
            lats.max()! + 0.01)
        return try await HTTP.postForm(
            URL(string: "https://services.ga.gov.au/gis/rest/services/DEM_LiDAR_5m_2025/MapServer/identify")!,
            fields: [
                "geometry": "{\"points\":[\(pointList)],\"spatialReference\":{\"wkid\":4326}}",
                "geometryType": "esriGeometryMultipoint", "sr": "4326", "layers": "all", "tolerance": "0",
                "mapExtent": extent, "imageDisplay": "400,400,96", "returnGeometry": "true", "f": "json",
            ])
    }
}

/// A WMS raster layer queried one point per request (`WMSPoint`), such as the City of Cape Town's lidar terrain model.
///
/// Requests start one per second, whatever their latency, as for GSI. A server under load can answer with a WMS
/// exception report instead of JSON; such a point is asked again a few times before the run stops.
struct WMSPointElevationProvider: ElevationProvider {
    let name = "wmsPoint"
    let batchSize = 30
    let settings: CourseConfig.WMSPointSettings

    func elevations(at points: [Coordinate]) async throws -> [ElevationReading] {
        try await withThrowingTaskGroup(of: (Int, ElevationReading).self) { group in
            for (index, point) in points.enumerated() {
                group.addTask {
                    try await Task.sleep(for: .seconds(Double(index)))
                    return (index, try await reading(at: point))
                }
            }
            var readings = [ElevationReading?](repeating: nil, count: points.count)
            for try await (index, reading) in group { readings[index] = reading }
            return readings.map { $0! }
        }
    }

    private func reading(at point: Coordinate, attempts: Int = 4) async throws -> ElevationReading {
        for attempt in 1... {
            do {
                return try WMSPoint.reading(from: try await HTTP.get(WMSPoint.url(settings, at: point)), settings)
            } catch let error as PipelineError where attempt < attempts {
                log("  WMS: \(error); asking again")
                try await Task.sleep(for: .seconds(5 * attempt))
            }
        }
        fatalError("unreachable")
    }
}

/// A WCS coverage read as small text grids (`WCSGrid`), such as the Environment Agency's 1 m lidar terrain model.
///
/// Points are split into runs that fit a ~250 m box, one request each, started 5 s apart: the Environment Agency's
/// gateway answers 403 to faster clients, and 403 is retried with back-off.
struct WCSGridElevationProvider: ElevationProvider {
    let name = "wcsGrid"
    let batchSize = 100
    let settings: CourseConfig.WCSGridSettings

    func elevations(at points: [Coordinate]) async throws -> [ElevationReading] {
        var readings: [ElevationReading] = []
        for run in WCSGrid.windows(points, maximumMeters: 250) {
            let started = ContinuousClock.now
            let batch = Array(points[run])
            let box = WCSGrid.window(for: batch)
            readings += try await reading(batch, box)
            try await Task.sleep(until: started + .seconds(5))
        }
        return readings
    }

    private func reading(
        _ points: [Coordinate], _ box: (south: Double, west: Double, north: Double, east: Double), attempts: Int = 4
    ) async throws -> [ElevationReading] {
        let url = try WCSGrid.url(settings, south: box.south, west: box.west, north: box.north, east: box.east)
        for attempt in 1... {
            do {
                return try WCSGrid.readings(from: try await HTTP.get(url, alsoRetrying: [403]), for: points, settings)
            } catch let error as PipelineError where attempt < attempts {
                log("  WCS: \(error); asking again")
                try await Task.sleep(for: .seconds(10 * attempt))
            }
        }
        fatalError("unreachable")
    }
}

/// Copernicus GLO-30 (`copernicus`), the global 30 m surface model, from AWS's cloud-optimised GeoTIFFs
/// (`CopernicusDEM`): for each 1° file the points fall in, the header first, then only the 1024 × 1024 internal tiles
/// the points need (about 3 MB each), with range requests. A surface model: it sees buildings and forest canopy, so
/// use it only where nothing better exists (the Great Wall). Every sample is labelled `COP30`.
struct CopernicusElevationProvider: ElevationProvider {
    let name = "copernicus"
    let batchSize = 100_000

    func elevations(at points: [Coordinate]) async throws -> [ElevationReading] {
        var readings = [ElevationReading?](repeating: nil, count: points.count)
        let files = Dictionary(grouping: points.indices) { CopernicusDEM.fileURL(for: points[$0]) }
        for (url, indices) in files.sorted(by: { $0.key.absoluteString < $1.key.absoluteString }) {
            log("  Copernicus: \(url.lastPathComponent)")
            let layout = try CopernicusDEM.layout(
                fromHeader: try await HTTP.get(url, bytes: 0..<CopernicusDEM.headerBytes))
            var tiles: [Int: [Float]] = [:]
            for tile in Set(indices.flatMap { layout.tiles(for: points[$0]) }).sorted() {
                let start = layout.tileOffsets[tile]
                let data = try await HTTP.get(url, bytes: start..<start + layout.tileByteCounts[tile])
                tiles[tile] = try CopernicusDEM.pixels(fromTile: data, layout: layout)
            }
            for i in indices {
                let value = layout.elevation(at: points[i], tiles: tiles)
                readings[i] = ElevationReading(
                    elevationMeters: value.map { ($0 * 1000).rounded() / 1000 },
                    source: value == nil ? "no data" : "COP30")
            }
        }
        return readings.map { $0! }
    }
}

/// No elevation data: every point is `baseMeters`, labelled `flat`. For a course with no usable open elevation data
/// (Shanghai, where global models show buildings, not ground); real bridge humps come from modelled profiles.
struct FlatElevationProvider: ElevationProvider {
    let name = "flat"
    let batchSize = 10_000
    let baseMeters: Double

    func elevations(at points: [Coordinate]) async throws -> [ElevationReading] {
        points.map { _ in ElevationReading(elevationMeters: baseMeters, source: "flat") }
    }
}

/// Geospatial Information Authority of Japan elevation API: one point per request.
///
/// Requests start one per second, whatever their latency, so the server sees a steady ~1 request/second.
struct GSIElevationProvider: ElevationProvider {
    let name = "gsi"
    let batchSize = 30

    func elevations(at points: [Coordinate]) async throws -> [ElevationReading] {
        try await withThrowingTaskGroup(of: (Int, ElevationReading).self) { group in
            for (index, point) in points.enumerated() {
                group.addTask {
                    try await Task.sleep(for: .seconds(Double(index)))
                    return (index, try await Self.reading(at: point))
                }
            }
            var readings = [ElevationReading?](repeating: nil, count: points.count)
            for try await (index, reading) in group { readings[index] = reading }
            return readings.map { $0! }
        }
    }

    private static func reading(at point: Coordinate) async throws -> ElevationReading {
        let url = URL(
            string: String(
                format:
                    "https://cyberjapandata2.gsi.go.jp/general/dem/scripts/getelevation.php?lon=%.7f&lat=%.7f&outtype=JSON",
                point.longitude, point.latitude))!
        let data = try await HTTP.get(url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PipelineError("unexpected GSI response")
        }
        let source = object["hsrc"] as? String ?? "unknown"
        if let elevation = object["elevation"] as? Double {
            return ElevationReading(elevationMeters: elevation, source: source)
        }
        // GSI returns "-----" where it has no data.
        return ElevationReading(elevationMeters: nil, source: "no data")
    }
}
