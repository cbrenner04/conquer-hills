import Foundation
import Testing

@testable import WorkoutKit

@Suite("Run history")
struct RunHistoryTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "RunHistoryTests-\(UUID())")
    private var store: RunHistoryStore { RunHistoryStore(directory: directory) }

    /// A finished Test Hills run at 6 mph with a speed change and a pause, ending early at `endAt` seconds.
    private func record(endAt: Double = 150) throws -> WorkoutRecord {
        var workout = try TestHills.workout()
        startRun(&workout)
        workout.setSpeed(.mph(7), at: at(23))
        workout.pause(at: at(43))
        workout.resume(at: at(73))
        workout.advance(to: at(endAt))
        workout.end(at: at(endAt))
        return workout.record
    }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test("A saved run lists back exactly")
    func roundTrip() throws {
        defer { cleanUp() }
        let record = try record()

        let saved = try store.save(record, savedAt: startDate.addingTimeInterval(200))

        #expect(store.list() == [saved])
        #expect(store.list().first?.record == record)
    }

    @Test("Runs list newest first")
    func newestFirst() throws {
        defer { cleanUp() }
        let record = try record()
        var older = record
        older.startedAt = startDate.addingTimeInterval(-86_400)

        let first = try store.save(older)
        let second = try store.save(record)

        #expect(store.list().map(\.id) == [second.id, first.id])
    }

    @Test("Deleting removes the run")
    func delete() throws {
        defer { cleanUp() }
        let entry = try store.save(try record())

        try store.delete(id: entry.id)

        #expect(store.list().isEmpty)
        #expect(throws: Never.self) { try store.delete(id: entry.id) }
    }

    @Test("Unreadable and future-schema files are skipped and left on disk")
    func unreadableFiles() throws {
        defer { cleanUp() }
        let good = try store.save(try record())
        let corrupt = directory.appending(path: "\(UUID().uuidString).json")
        try Data("not json".utf8).write(to: corrupt)
        let futureEntry = RunHistoryEntry(savedAt: Date(), record: try record())
        var futureJSON =
            try JSONSerialization.jsonObject(
                with: RunHistoryStore.exportData([futureEntry])) as! [[String: Any]]
        futureJSON[0]["schemaVersion"] = 99
        let future = directory.appending(path: "\(futureEntry.id.uuidString).json")
        try JSONSerialization.data(withJSONObject: futureJSON[0]).write(to: future)

        #expect(store.list().map(\.id) == [good.id])
        #expect(FileManager.default.fileExists(atPath: corrupt.path))
        #expect(FileManager.default.fileExists(atPath: future.path))
    }

    @Test("An empty or missing directory lists nothing")
    func emptyStore() {
        #expect(store.list().isEmpty)
    }

    @Test("Export is a JSON array of every run")
    func export() throws {
        defer { cleanUp() }
        let a = try store.save(try record())
        let b = try store.save(try record(endAt: 300))

        let data = try RunHistoryStore.exportData(store.list())

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([RunHistoryEntry].self, from: data)
        #expect(Set(decoded.map(\.id)) == [a.id, b.id])
    }

    @Test("Only runs with at least a minute of running are kept")
    func minimumDuration() throws {
        var short = try TestHills.workout()
        startRun(&short)
        short.end(at: at(50))  // 47 s of running
        var long = try TestHills.workout()
        startRun(&long)
        long.end(at: at(63))  // exactly 60 s
        var unfinished = try TestHills.workout()
        startRun(&unfinished)
        unfinished.advance(to: at(200))

        #expect(!RunHistoryStore.shouldSave(short.record))
        #expect(RunHistoryStore.shouldSave(long.record))
        #expect(!RunHistoryStore.shouldSave(unfinished.record))
    }

    @Test("Totals count runs and distance, overall and in the last 7 days")
    func totals() throws {
        let record = try record()
        let now = startDate.addingTimeInterval(3600)
        var lastMonth = record
        lastMonth.startedAt = now.addingTimeInterval(-30 * 86_400)
        let entries = [
            RunHistoryEntry(savedAt: now, record: record), RunHistoryEntry(savedAt: now, record: lastMonth),
        ]

        #expect(RunTotals(entries) == RunTotals(runs: 2, distanceMeters: record.distanceMeters * 2))
        #expect(RunTotals.lastSevenDays(entries, now: now).runs == 1)
    }
}

@Suite("Run chart data")
struct RunChartDataTests {
    @Test("Incline steps start at the starting incline, follow each change, and run to the end")
    func inclineSteps() throws {
        var workout = try TestHills.workout()
        startRun(&workout)
        workout.advance(to: at(3 + 450 / sixMph))
        workout.end(at: at(3 + 450 / sixMph))

        let chart = RunChartData(workout.record)

        #expect(chart.incline.map(\.value) == [1, 3, 6.5, 6.5])
        #expect(chart.incline.map(\.distanceMeters).dropLast() == [0, 200, 400])
        #expect(isClose(chart.incline.last?.distanceMeters ?? 0, 450))
        #expect(chart.speed.isEmpty)
        #expect(chart.pauseDistancesMeters.isEmpty)
    }

    @Test("Speed steps and pauses appear when the run had them")
    func speedAndPauses() throws {
        var workout = try TestHills.workout()
        startRun(&workout)
        workout.setSpeed(.mph(7), at: at(23))
        workout.pause(at: at(43))
        workout.resume(at: at(73))
        workout.end(at: at(100))

        let chart = RunChartData(workout.record)

        #expect(chart.speed.map(\.value) == [6, 7, 7])
        #expect(isClose(chart.speed[1].distanceMeters, 20 * sixMph))
        #expect(chart.pauseDistancesMeters.count == 1)
    }
}
