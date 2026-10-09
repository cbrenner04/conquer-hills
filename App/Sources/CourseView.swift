import CourseKit
import SwiftUI
import WorkoutKit

/// One screen per course: its profile, facts, segment choice (including custom), run settings, a preview of the
/// run, Start, and where the data comes from.
struct CourseView: View {
    let course: Course
    /// Returns to the course list.
    let onDone: () -> Void

    @AppStorage("lastSpeedMph") private var lastSpeedMph = 6.0
    @AppStorage("baselinePercent") private var baselinePercent = 1.0
    @State private var selection: Selection = .predefined("full-course")
    @State private var customRange: CustomSegmentRange
    @State private var run: RunModel?
    @Environment(RunHistoryModel.self) private var history

    static let baselineChoices: [Double] = [0, 0.5, 1, 1.5, 2]

    enum Selection: Hashable {
        case predefined(String)
        case custom
    }

    init(course: Course, onDone: @escaping () -> Void) {
        self.course = course
        self.onDone = onDone
        _customRange = State(initialValue: CustomSegmentRange(courseMeters: course.distanceMeters))
    }

    private var segment: CourseSegment {
        switch selection {
        case .predefined(let id):
            course.predefinedSegments.first { $0.id == id } ?? course.fullCourseSegment
        case .custom:
            customRange.segment(in: course) ?? course.fullCourseSegment
        }
    }

    private var settings: TreadmillSettings { TreadmillSettings(baselinePercent: baselinePercent) }
    private var speed: Speed { .mph(lastSpeedMph) }
    private var profile: TreadmillProfile { TreadmillProfile(course: course, segment: segment, settings: settings) }

    var body: some View {
        Form {
            Section {
                CourseProfileChart(course: course, segment: segment)
                    .padding(.top, 16)
                facts
            }

            Section("Segment") {
                ForEach(course.predefinedSegments) { candidate in
                    segmentRow(
                        candidate.name ?? "Custom", detail: detail(candidate), selection: .predefined(candidate.id)
                    )
                    .accessibilityIdentifier("segment-\(candidate.id)")
                }
                segmentRow("Custom", detail: "Choose your own start and end", selection: .custom)
                    .accessibilityIdentifier("segment-custom")
                if selection == .custom {
                    boundaryRow("Start", meters: customRange.startMeters, id: "start") {
                        customRange.moveStart(bySteps: $0)
                    }
                    boundaryRow("End", meters: customRange.endMeters, id: "end") { customRange.moveEnd(bySteps: $0) }
                }
                Text(
                    "Run \(RunFormatting.miles(segment.distanceMeters, decimals: 1)), from course mi \(RunFormatting.mileNumber(segment.startMeters)) to \(RunFormatting.mileNumber(segment.endMeters))"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Section("Starting speed") {
                SpeedControl(speed: speed) { lastSpeedMph = $0.mph }
            }

            Section {
                Picker("Baseline incline", selection: $baselinePercent) {
                    ForEach(Self.baselineChoices, id: \.self) { choice in
                        Text(RunFormatting.incline(choice)).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Baseline incline")
            } footer: {
                Text(
                    "Added to the course's grade. Flat road becomes this incline, so downhills still show on a treadmill that can't decline."
                )
            }

            Section {
                startPanel
            }

            Section("About this data") {
                dataNotes
            }
        }
        .navigationTitle(course.name)
        .fullScreenCover(item: $run) { model in
            ActiveRunView(
                model: model,
                onDone: {
                    run = nil
                    onDone()
                },
                onRunAgain: { run = nil })
        }
    }

    // MARK: Sections

    private var facts: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            fact("Location", course.location)
            fact("Edition", course.edition)
            fact("Distance", RunFormatting.miles(course.distanceMeters))
            fact(
                "Gain / loss",
                "↑ \(RunFormatting.feet(course.stats.elevationGainMeters)) · ↓ \(RunFormatting.feet(course.stats.elevationLossMeters))"
            )
            fact(
                "Low / high",
                "\(RunFormatting.feet(course.stats.minimumElevationMeters)) – \(RunFormatting.feet(course.stats.maximumElevationMeters))"
            )
        }
        .font(.subheadline)
        .padding(.vertical, 4)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }

    private func segmentRow(_ title: String, detail: String, selection target: Selection) -> some View {
        Button {
            if target == .custom && selection != .custom {
                // Start the custom range from whatever was selected, so it's a small adjustment.
                customRange = CustomSegmentRange(
                    courseMeters: course.distanceMeters, startMeters: segment.startMeters, endMeters: segment.endMeters)
            }
            selection = target
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if selection == target {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
        .tint(.primary)
    }

    private func detail(_ segment: CourseSegment) -> String {
        let distance = RunFormatting.miles(segment.distanceMeters, decimals: 1)
        guard segment.startMeters > 0 || segment.endMeters < course.distanceMeters else { return distance }
        return
            "\(distance) · mi \(RunFormatting.mileNumber(segment.startMeters))–\(RunFormatting.mileNumber(segment.endMeters))"
    }

    private func boundaryRow(_ label: String, meters: Double, id: String, move: @escaping (Int) -> Void) -> some View {
        let isStart = id == "start"
        let canEarlier = isStart ? customRange.canMoveStartEarlier : customRange.canMoveEndEarlier
        let canLater = isStart ? customRange.canMoveStartLater : customRange.canMoveEndLater
        return HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text("mi \(RunFormatting.mileNumber(meters))").font(.title3.bold().monospacedDigit())
            }
            Spacer()
            stepButton("−1", steps: -10, enabled: canEarlier, id: "custom-\(id)--10", move: move)
            stepButton("−", steps: -1, enabled: canEarlier, id: "custom-\(id)--1", move: move)
            stepButton("+", steps: 1, enabled: canLater, id: "custom-\(id)-1", move: move)
            stepButton("+1", steps: 10, enabled: canLater, id: "custom-\(id)-10", move: move)
        }
    }

    private func stepButton(_ title: String, steps: Int, enabled: Bool, id: String, move: @escaping (Int) -> Void)
        -> some View
    {
        Button(title) { move(steps) }
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .frame(minWidth: 40, minHeight: 40)
            .buttonStyle(.bordered)
            .disabled(!enabled)
            .accessibilityIdentifier(id)
    }

    private var startPanel: some View {
        let preview = RunPreview(profile: profile, speed: speed)
        return VStack(spacing: 14) {
            Text(
                "**\(preview.inclineChangeCount)** incline \(preview.inclineChangeCount == 1 ? "change" : "changes") · about **\(RunFormatting.duration(preview.estimatedDuration))** at \(RunFormatting.speed(speed))"
            )
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .accessibilityIdentifier("run-preview")
            Text("Set your treadmill to **\(RunFormatting.incline(preview.startingInclinePercent))**")
                .font(.title3)
            Button {
                startRun()
            } label: {
                Text("Start")
                    .font(.title.bold())
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("start")
            Text("Incline prompts approximate the course. Only change settings when it's safe to.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var dataNotes: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let description = course.description {
                Text(description)
            }
            if let attribution = course.source.attribution {
                Text(attribution)
            }
            Text("Route: \(course.source.route.name) (\(course.source.route.license))")
            Text("Elevation: \(course.source.elevation.name) (\(course.source.elevation.license))")
            Text(
                course.source.elevation.kind == .modeled
                    ? "Elevations are modelled from terrain data and may differ from the course, especially on bridges."
                    : "Elevations are measured.")
            Text(
                course.source.isVerified
                    ? "The route has been checked against the official course map."
                    : "The route hasn't yet been checked against the official course map.")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private func startRun() {
        let samples = ElevationChartData.downsample(
            ElevationChartData.slice(course.elevationProfile, from: segment.startMeters, to: segment.endMeters),
            maximumPoints: 200)
        let model = RunModel(
            course: course, segment: segment, settings: settings, startingSpeed: speed, history: history,
            profileSamples: samples)
        run = model
        model.start()
    }
}
