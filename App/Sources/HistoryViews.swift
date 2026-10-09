import Charts
import SwiftUI
import WorkoutKit

/// Saved runs, newest first, grouped by month, with totals.
struct HistoryListView: View {
    @Environment(RunHistoryModel.self) private var history
    @State private var pendingDelete: RunHistoryEntry?

    private var months: [(start: Date, entries: [RunHistoryEntry])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: history.entries) {
            calendar.dateInterval(of: .month, for: $0.date)?.start ?? $0.date
        }
        return groups.keys.sorted(by: >).map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        List {
            if !history.entries.isEmpty {
                Section {
                    totalsRow("Last 7 days", RunTotals.lastSevenDays(history.entries, now: Date()))
                    totalsRow("All time", RunTotals(history.entries))
                }
            }
            ForEach(months, id: \.start) { month in
                Section(month.start.formatted(.dateTime.month(.wide).year())) {
                    ForEach(month.entries) { entry in
                        NavigationLink {
                            RunDetailView(entry: entry)
                        } label: {
                            HistoryRow(entry: entry)
                        }
                        .accessibilityIdentifier("history-run")
                        .swipeActions {
                            Button("Delete", role: .destructive) { pendingDelete = entry }
                        }
                    }
                }
            }
        }
        .navigationTitle("History")
        .overlay {
            if history.entries.isEmpty {
                ContentUnavailableView(
                    "No runs yet", systemImage: "figure.run", description: Text("Finished runs appear here."))
            }
        }
        .toolbar {
            if !history.entries.isEmpty {
                ShareLink(
                    item: RunExport(entries: history.entries, fileName: "conquer-hills-runs.json"),
                    preview: SharePreview("Conquer Hills runs")
                ) {
                    Label("Export all", systemImage: "square.and.arrow.up")
                }
            }
        }
        .confirmationDialog(
            "Delete this run?", isPresented: .constant(pendingDelete != nil), titleVisibility: .visible,
            presenting: pendingDelete
        ) { entry in
            Button("Delete", role: .destructive) {
                history.delete(entry.id)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
        .onAppear { history.reload() }
    }

    private func totalsRow(_ label: String, _ totals: RunTotals) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(totals.runs) \(totals.runs == 1 ? "run" : "runs") · \(RunFormatting.miles(totals.distanceMeters))")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

private struct HistoryRow: View {
    let entry: RunHistoryEntry

    var body: some View {
        let record = entry.record
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                OutcomeBadge(outcome: record.outcome)
            }
            Text("\(record.course.name) · \(record.segment.name ?? "Custom segment")")
                .font(.headline)
            Text(
                "\(RunFormatting.miles(record.distanceMeters)) · \(RunFormatting.duration(record.activeDuration)) · \(record.averageSpeed.map(RunFormatting.speed) ?? "—")"
            )
            .font(.subheadline.monospacedDigit())
        }
        .padding(.vertical, 2)
    }
}

private struct OutcomeBadge: View {
    let outcome: WorkoutRecord.Outcome?

    var body: some View {
        let finished = outcome == .finished
        Text(finished ? "Finished" : "Ended early")
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(finished ? Color.green.opacity(0.2) : Color.orange.opacity(0.2)))
            .foregroundStyle(finished ? .green : .orange)
    }
}

/// One saved run: stats, incline and speed charts, export and delete.
struct RunDetailView: View {
    let entry: RunHistoryEntry
    @Environment(RunHistoryModel.self) private var history
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false

    private var record: WorkoutRecord { entry.record }
    private var chart: RunChartData { RunChartData(record) }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(record.course.name) · \(record.segment.name ?? "Custom segment")").font(.headline)
                    Text(entry.date.formatted(date: .complete, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if record.segment.startMeters > 0 {
                        Text(
                            "Course mi \(RunFormatting.mileNumber(record.segment.startMeters))–\(RunFormatting.mileNumber(record.segment.startMeters + record.distanceMeters))"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }
                RunStatsGrid(record: record)
            }

            Section("Incline") {
                StepChart(steps: chart.incline, pauses: chart.pauseDistancesMeters, unit: "%", tint: .orange)
            }

            if !chart.speed.isEmpty {
                Section("Speed") {
                    StepChart(steps: chart.speed, pauses: chart.pauseDistancesMeters, unit: "mph", tint: .blue)
                }
            }

            Section {
                Button("Delete run", role: .destructive) { confirmingDelete = true }
            }
        }
        .navigationTitle("Run")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ShareLink(
                item: RunExport(entries: [entry], fileName: "conquer-hills-run-\(entry.id.uuidString.prefix(8)).json"),
                preview: SharePreview("Conquer Hills run")
            )
        }
        .confirmationDialog("Delete this run?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                history.delete(entry.id)
                dismiss()
            }
        }
    }
}

/// A step chart of a value against miles, with pauses marked.
private struct StepChart: View {
    let steps: [RunChartData.Step]
    let pauses: [Double]
    let unit: String
    let tint: Color

    var body: some View {
        Chart {
            ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                LineMark(
                    x: .value("Distance", step.distanceMeters / RunFormatting.metersPerMile),
                    y: .value(unit, step.value)
                )
                .interpolationMethod(.stepEnd)
                .foregroundStyle(tint)
            }
            ForEach(Array(pauses.enumerated()), id: \.offset) { _, distance in
                RuleMark(x: .value("Pause", distance / RunFormatting.metersPerMile))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .center) {
                        Image(systemName: "pause.fill").font(.caption2).foregroundStyle(.secondary)
                    }
            }
        }
        .chartXAxisLabel("mi")
        .chartYAxisLabel(unit)
        .frame(height: 180)
        .padding(.vertical, 8)
        .accessibilityLabel("\(unit) over distance")
    }
}

/// The run's headline figures, shared by the summary and the history detail.
struct RunStatsGrid: View {
    let record: WorkoutRecord
    var font: Font = .body

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
            row("Distance", RunFormatting.miles(record.distanceMeters))
            row("Time", RunFormatting.duration(record.activeDuration))
            row("Average speed", record.averageSpeed.map(RunFormatting.speed) ?? "—")
            row("Incline changes", "\(record.inclineChanges.count)")
            row("Highest incline", RunFormatting.incline(record.maximumInclinePercent))
            row("Baseline", RunFormatting.incline(record.settings.baselinePercent))
        }
        .font(font.monospacedDigit())
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).bold()
        }
    }
}
