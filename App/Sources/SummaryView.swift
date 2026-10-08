import SwiftUI
import WorkoutKit

/// Shown when a run finishes or is ended: what was run and how it went. Not saved yet (spec 08).
struct SummaryView: View {
    let record: WorkoutRecord
    let onDone: () -> Void
    let onRunAgain: () -> Void

    var body: some View {
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

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                row("Distance", RunFormatting.miles(record.distanceMeters))
                row("Time", RunFormatting.duration(record.activeDuration))
                row("Average speed", record.averageSpeed.map(RunFormatting.speed) ?? "—")
                row("Incline changes", "\(record.inclineChanges.count)")
                row("Highest incline", RunFormatting.incline(record.maximumInclinePercent))
                row("Baseline", RunFormatting.incline(record.settings.baselinePercent))
            }
            .font(.title3.monospacedDigit())

            Spacer()

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
        }
        .padding(24)
        .foregroundStyle(.white)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).bold()
        }
    }
}
