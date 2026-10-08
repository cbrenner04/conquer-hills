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

    /// The member ways of a route relation, chained into one line.
    static func relationRoute(id: Int, start: Coordinate) async throws -> (line: [Coordinate], timestamp: String) {
        let response = try await query("[out:json][timeout:180];relation(\(id));way(r);out body;>;out skel qt;")
        var nodes: [Int: Coordinate] = [:]
        var ways: [RelationChaining.Way] = []
        for element in response.elements {
            if element.type == "node", let lat = element.lat, let lon = element.lon {
                nodes[element.id] = Coordinate(latitude: lat, longitude: lon)
            } else if element.type == "way", let wayNodes = element.nodes {
                ways.append(.init(id: element.id, nodes: wayNodes))
            }
        }
        let chained = try RelationChaining.chain(ways: ways, nodeLocations: nodes, start: start)
        return (chained.compactMap { nodes[$0] }, response.osm3s.timestampOSMBase)
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
