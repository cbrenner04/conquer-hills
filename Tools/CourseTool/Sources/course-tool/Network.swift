import CourseToolCore
import Foundation

/// Polite HTTP: identifies the tool, retries transient failures with backoff.
enum HTTP {
    static let userAgent = "conquer-hills-course-tool (https://github.com/cbrenner04/conquer-hills)"

    static func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return try await send(request)
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
        return try await send(request)
    }

    private static func send(_ request: URLRequest, attempts: Int = 5) async throws -> Data {
        var delay: Duration = .seconds(5)
        for attempt in 1...attempts {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 200 { return data }
                if attempt == attempts || ![429, 500, 502, 503, 504].contains(status) {
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
        let projection = Geo.Projection(fitting: line)
        let simplified = Geo.simplify(line.map(projection.point), toleranceMeters: 5).map(projection.coordinate)
        let polyline = simplified.map { String(format: "%.6f,%.6f", $0.latitude, $0.longitude) }
            .joined(separator: ",")
        let around = "around:\(Int(bufferMeters)),\(polyline)"
        let ql = """
            [out:json][timeout:180];
            (
              way(\(around))["bridge"]["bridge"!="no"];
              way(\(around))["tunnel"]["tunnel"!="no"];
              way(\(around))["covered"="yes"];
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
        let polyline = waypoints.map { String(format: "%.6f,%.6f", $0.latitude, $0.longitude) }
            .joined(separator: ",")
        let highways = (settings.highways ?? RouteGraph.defaultHighways).joined(separator: "|")
        let extra =
            settings.includeWays.isEmpty
            ? "" : "way(id:\(settings.includeWays.map(String.init).joined(separator: ",")));"
        let response = try await Overpass.query(
            """
            [out:json][timeout:300];
            (
              way(around:\(Int(settings.corridorMeters)),\(polyline))["highway"~"^(\(highways))$"];
              \(extra)
            );
            out meta;
            >;
            out skel qt;
            """)
        let (ways, nodes) = graphData(response.elements)
        return Corridor(ways: ways, nodes: nodes, source: "Overpass", timestamp: response.osm3s.timestampOSMBase)
    }

    private static func mapBoxes(around waypoints: [Coordinate], settings: CourseConfig.OSMGraphSettings)
        async throws -> Corridor
    {
        // Boxes no longer than ~1 km along the waypoint line, padded by the corridor, stay far below the API's
        // area and node limits.
        var boxes: [(south: Double, west: Double, north: Double, east: Double)] = []
        for (a, b) in zip(waypoints, waypoints.dropFirst()) {
            let pieces = max(1, Int((Geo.distance(a, b) / 1000).rounded(.up)))
            for k in 0..<pieces {
                func at(_ t: Double) -> Coordinate {
                    Coordinate(
                        latitude: a.latitude + (b.latitude - a.latitude) * t,
                        longitude: a.longitude + (b.longitude - a.longitude) * t)
                }
                let p = at(Double(k) / Double(pieces))
                let q = at(Double(k + 1) / Double(pieces))
                let padLatitude = settings.corridorMeters / 111_195
                let padLongitude = padLatitude / cos(p.latitude * .pi / 180)
                boxes.append(
                    (
                        min(p.latitude, q.latitude) - padLatitude, min(p.longitude, q.longitude) - padLongitude,
                        max(p.latitude, q.latitude) + padLatitude, max(p.longitude, q.longitude) + padLongitude
                    ))
            }
        }
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

/// USGS 3D Elevation Program, through the 3DEP ImageServer's batch `getSamples`.
///
/// Each point gets the best available DEM (1 m lidar where it exists); the source label is that dataset's project
/// name, e.g. `MA_CentralEastern_2021_B21`. The service advertises 2,000 points a request but can silently return
/// fewer samples than points, so requests are kept to 500 points and any point left out of a response is asked for
/// again. Requests are spaced a few seconds apart.
struct USGS3DEPElevationProvider: ElevationProvider {
    let name = "usgs3dep"
    let batchSize = 500

    func elevations(at points: [Coordinate]) async throws -> [ElevationReading] {
        var readings = [ElevationReading?](repeating: nil, count: points.count)
        for attempt in 1...4 {
            let pending = points.indices.filter { readings[$0] == nil }
            if pending.isEmpty { break }
            if attempt > 1 { log("  3DEP: asking again for \(pending.count) points left out of the response") }
            let returned = try await Self.samples(at: pending.map { points[$0] })
            for (offset, reading) in returned { readings[pending[offset]] = reading }
            try await Task.sleep(for: .seconds(3))
        }
        guard readings.allSatisfy({ $0 != nil }) else {
            throw PipelineError("3DEP kept leaving points out of its responses; try again later")
        }
        return readings.map { $0! }
    }

    /// The samples the service returned, keyed by position in `points`. A sample whose value isn't a number is
    /// recorded as no data; a point missing from the response is left out, so it can be asked for again.
    private static func samples(at points: [Coordinate]) async throws -> [Int: ElevationReading] {
        let pointList = points.map { String(format: "[%.7f,%.7f]", $0.longitude, $0.latitude) }.joined(separator: ",")
        let url = URL(
            string: "https://elevation.nationalmap.gov/arcgis/rest/services/3DEPElevation/ImageServer/getSamples")!
        let data = try await HTTP.postForm(
            url,
            fields: [
                "geometry": "{\"points\":[\(pointList)],\"spatialReference\":{\"wkid\":4326}}",
                "geometryType": "esriGeometryMultipoint", "returnFirstValueOnly": "true",
                "interpolation": "RSP_BilinearInterpolation", "outFields": "Name", "f": "json",
            ])
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
        guard let samples = try JSONDecoder().decode(Response.self, from: data).samples else {
            throw PipelineError("unexpected 3DEP response: \(String(decoding: data.prefix(300), as: UTF8.self))")
        }
        var result: [Int: ElevationReading] = [:]
        for sample in samples where sample.locationId >= 0 && sample.locationId < points.count {
            if let value = Double(sample.value) {
                result[sample.locationId] = ElevationReading(
                    elevationMeters: (value * 1000).rounded() / 1000, source: sample.attributes?.name ?? "unknown")
            } else {
                result[sample.locationId] = ElevationReading(elevationMeters: nil, source: "no data")
            }
        }
        return result
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
