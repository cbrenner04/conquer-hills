import Foundation
import os

/// One saved run: a `WorkoutRecord` with an identity, the time it was saved, and the runner's own reflection on
/// it ("How'd it go?").
public struct RunHistoryEntry: Identifiable, Equatable, Sendable, Codable {
    public static let currentSchemaVersion = 1
    public static let ratingRange = 1...5

    public let schemaVersion: Int
    public let id: UUID
    public let savedAt: Date
    public let record: WorkoutRecord
    /// The runner's star rating, 1–5, or nil if not rated. Optional so runs saved before it existed still load.
    public private(set) var rating: Int?
    /// The runner's notes to self, or nil if there are none.
    public private(set) var notes: String?

    public init(id: UUID = UUID(), savedAt: Date, record: WorkoutRecord, rating: Int? = nil, notes: String? = nil) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.savedAt = savedAt
        self.record = record
        setReflection(rating: rating, notes: notes)
    }

    /// Sets the rating and notes. A rating outside 1–5 is clamped; notes are trimmed, and empty notes become nil.
    public mutating func setReflection(rating: Int?, notes: String?) {
        self.rating = rating.map { min(max($0, Self.ratingRange.lowerBound), Self.ratingRange.upperBound) }
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.notes = trimmed.isEmpty ? nil : trimmed
    }

    /// When the run started, or when it was saved if it never started.
    public var date: Date { record.startedAt ?? savedAt }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        id = try container.decode(UUID.self, forKey: .id)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        record = try container.decode(WorkoutRecord.self, forKey: .record)
        // Absent in runs saved before reflections existed; normalized like any other input.
        setReflection(
            rating: try container.decodeIfPresent(Int.self, forKey: .rating),
            notes: try container.decodeIfPresent(String.self, forKey: .notes))
    }
}

/// Saved runs as one JSON file per run (`<id>.json`) in a directory, normally Application Support/RunHistory.
///
/// Files that can't be read (corrupt, or written by a newer schema) are skipped, logged, and left on disk.
/// `WorkoutRecord` must stay decodable from old files: add fields as optional or with defaults, or bump
/// `RunHistoryEntry.currentSchemaVersion` with a migration.
public struct RunHistoryStore: Sendable {
    /// Runs with less active time than this aren't saved (e.g. a mistaken start ended straight away).
    public static let minimumActiveDuration: Duration = .seconds(60)

    public let directory: URL

    private static let logger = Logger(subsystem: "com.hills-app.conquerhills", category: "RunHistory")

    public init(directory: URL) {
        self.directory = directory
    }

    /// The app's store, in Application Support/RunHistory.
    public static func standard() throws -> RunHistoryStore {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return RunHistoryStore(directory: support.appending(path: "RunHistory"))
    }

    /// Whether a finished or ended run is worth keeping.
    public static func shouldSave(_ record: WorkoutRecord) -> Bool {
        record.outcome != nil && record.activeDuration >= minimumActiveDuration
    }

    /// Saves a run and returns its entry.
    @discardableResult
    public func save(_ record: WorkoutRecord, id: UUID = UUID(), savedAt: Date = Date()) throws -> RunHistoryEntry {
        let entry = RunHistoryEntry(id: id, savedAt: savedAt, record: record)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder.encode(entry).write(to: url(for: id), options: .atomic)
        return entry
    }

    /// Every readable saved run, newest first. Unreadable files are skipped and logged.
    public func list() -> [RunHistoryEntry] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        var entries: [RunHistoryEntry] = []
        for name in names where name.hasSuffix(".json") {
            let url = directory.appending(path: name)
            do {
                let entry = try Self.decoder.decode(RunHistoryEntry.self, from: Data(contentsOf: url))
                guard entry.schemaVersion <= RunHistoryEntry.currentSchemaVersion else {
                    Self.logger.error("Skipping \(name, privacy: .public): schema version \(entry.schemaVersion)")
                    continue
                }
                entries.append(entry)
            } catch {
                Self.logger.error("Skipping unreadable run \(name, privacy: .public): \(error, privacy: .public)")
            }
        }
        return entries.sorted { $0.date > $1.date }
    }

    /// Updates a saved run's rating and notes, returning the new entry, or nil if the run isn't in the store.
    @discardableResult
    public func updateReflection(id: UUID, rating: Int?, notes: String?) throws -> RunHistoryEntry? {
        let url = url(for: id)
        guard let data = try? Data(contentsOf: url),
            var entry = try? Self.decoder.decode(RunHistoryEntry.self, from: data)
        else { return nil }
        entry.setReflection(rating: rating, notes: notes)
        try Self.encoder.encode(entry).write(to: url, options: .atomic)
        return entry
    }

    public func delete(id: UUID) throws {
        let url = url(for: id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// The given runs as a pretty-printed JSON array, for sharing.
    public static func exportData(_ entries: [RunHistoryEntry]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(entries)
    }

    private func url(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).json")
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// Number of runs and distance, for the history header.
public struct RunTotals: Equatable, Sendable {
    public let runs: Int
    public let distanceMeters: Double

    public init(runs: Int, distanceMeters: Double) {
        self.runs = runs
        self.distanceMeters = distanceMeters
    }

    public init(_ entries: some Sequence<RunHistoryEntry>) {
        var runs = 0
        var distance = 0.0
        for entry in entries {
            runs += 1
            distance += entry.record.distanceMeters
        }
        self.runs = runs
        self.distanceMeters = distance
    }

    /// Totals for runs in the 7 days up to `now`.
    public static func lastSevenDays(_ entries: [RunHistoryEntry], now: Date) -> RunTotals {
        let start = now.addingTimeInterval(-7 * 24 * 60 * 60)
        return RunTotals(entries.filter { $0.date > start && $0.date <= now })
    }
}

/// Step-chart data rebuilt from a run record. Distances are meters into the workout.
public struct RunChartData: Equatable, Sendable {
    public struct Step: Equatable, Sendable {
        public let distanceMeters: Double
        public let value: Double
    }

    /// Incline the runner was told to use, from the start to the end of the run. The last step repeats the final
    /// value at the run's end distance so the chart extends to it.
    public let incline: [Step]
    /// Speed in mph over the run, in the same form; empty when the speed never changed.
    public let speed: [Step]
    /// Where the runner paused.
    public let pauseDistancesMeters: [Double]

    public init(_ record: WorkoutRecord) {
        let end = record.distanceMeters
        var incline = [Step(distanceMeters: 0, value: record.startingInclinePercent)]
        incline += record.inclineChanges.map { Step(distanceMeters: $0.distanceMeters, value: $0.toPercent) }
        incline.append(Step(distanceMeters: end, value: incline.last?.value ?? record.startingInclinePercent))
        self.incline = incline

        if record.speedChanges.isEmpty {
            speed = []
        } else {
            var speed = [Step(distanceMeters: 0, value: record.startingSpeed.mph)]
            speed += record.speedChanges.map { Step(distanceMeters: $0.distanceMeters, value: $0.speed.mph) }
            speed.append(Step(distanceMeters: end, value: speed.last?.value ?? record.startingSpeed.mph))
            self.speed = speed
        }
        pauseDistancesMeters = record.pauses.map(\.distanceMeters)
    }
}
