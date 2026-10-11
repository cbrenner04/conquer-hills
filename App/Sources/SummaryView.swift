import SwiftUI
import WorkoutKit

/// Shown when a run finishes or is ended: what was run, how it went, whether it was saved to history, and (for
/// saved runs) the runner's own rating and notes.
struct SummaryView: View {
    let record: WorkoutRecord
    let isSaved: Bool
    let onDelete: () -> Void
    /// Saves the runner's rating and notes for this run.
    let onReflect: (Int?, String) -> Void
    let onDone: () -> Void
    let onRunAgain: () -> Void

    @State private var confirmingDelete = false
    @State private var deleted = false
    @State private var rating: Int?
    @State private var notes = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 6) {
                    Image(systemName: record.outcome == .finished ? "flag.checkered" : "stop.circle")
                        .font(.system(size: 56))
                    Text(record.outcome == .finished ? "Course complete" : "Run ended")
                        .font(.largeTitle.bold())
                    Text("\(record.course.name) · \(record.segment.name ?? "Custom segment")")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                RunStatsGrid(record: record, font: .title3)

                savedState

                if isSaved && !deleted {
                    RunReflectionEditor(rating: $rating, notes: $notes)
                }
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button(action: onDone) {
                    Text("Done").font(.title2.bold()).frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("done")
                Button(action: onRunAgain) {
                    Text("Run again").font(.title3).frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.black)
        }
        .foregroundStyle(.white)
        .onChange(of: rating) { onReflect(rating, notes) }
        .onChange(of: notes) { onReflect(rating, notes) }
        .confirmationDialog("Delete this run?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                onDelete()
                deleted = true
            }
        }
    }

    @ViewBuilder
    private var savedState: some View {
        if deleted {
            Label("Deleted from history", systemImage: "trash")
                .foregroundStyle(.secondary)
        } else if isSaved {
            HStack(spacing: 16) {
                Label("Saved to history", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Button("Delete this run", role: .destructive) { confirmingDelete = true }
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        } else {
            Label("Not saved: under a minute of running", systemImage: "info.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
