import CoreTransferable
import Foundation
import Observation
import UniformTypeIdentifiers
import WorkoutKit

/// The app's saved runs, shared through the environment. Storage and its rules live in `RunHistoryStore`.
@Observable
final class RunHistoryModel {
    private let store: RunHistoryStore?
    private(set) var entries: [RunHistoryEntry] = []

    init(store: RunHistoryStore? = try? .standard()) {
        self.store = store
        reload()
    }

    func reload() {
        entries = store?.list() ?? []
    }

    /// Saves a finished or ended run if it had at least a minute of running. Returns the saved entry's id.
    func save(_ record: WorkoutRecord) -> UUID? {
        guard RunHistoryStore.shouldSave(record), let store, let entry = try? store.save(record) else { return nil }
        reload()
        return entry.id
    }

    func delete(_ id: UUID) {
        try? store?.delete(id: id)
        reload()
    }
}

/// Saved runs as a JSON file for the share sheet.
struct RunExport: Transferable {
    let entries: [RunHistoryEntry]
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { export in
            let url = FileManager.default.temporaryDirectory.appending(path: export.fileName)
            try RunHistoryStore.exportData(export.entries).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
