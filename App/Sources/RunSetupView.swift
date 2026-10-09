import CourseKit
import SwiftUI
import WorkoutKit

/// Choose a segment, starting speed, and baseline, then start the run.
struct RunSetupView: View {
    let course: Course
    /// Returns to the course list.
    let onDone: () -> Void

    @AppStorage("lastSpeedMph") private var lastSpeedMph = 6.0
    @AppStorage("baselinePercent") private var baselinePercent = 1.0
    @State private var segmentID = "full-course"
    @State private var run: RunModel?
    @Environment(RunHistoryModel.self) private var history

    static let baselineChoices: [Double] = [0, 0.5, 1, 1.5, 2]

    private var segment: CourseSegment {
        course.predefinedSegments.first { $0.id == segmentID } ?? course.fullCourseSegment
    }

    private var settings: TreadmillSettings {
        TreadmillSettings(baselinePercent: baselinePercent)
    }

    private var startingIncline: Double {
        TreadmillProfile(course: course, segment: segment, settings: settings).intervals.first?.inclinePercent ?? 0
    }

    private var speed: Speed { .mph(lastSpeedMph) }

    var body: some View {
        Form {
            Section("Segment") {
                ForEach(course.predefinedSegments) { candidate in
                    Button {
                        segmentID = candidate.id
                    } label: {
                        HStack {
                            SegmentLabel(segment: candidate, courseDistance: course.distanceMeters)
                            Spacer()
                            if candidate.id == segmentID {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .tint(.primary)
                }
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
                VStack(spacing: 16) {
                    Text("Set your treadmill to **\(RunFormatting.incline(startingIncline))**")
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

    private func startRun() {
        let model = RunModel(
            course: course, segment: segment, settings: settings, startingSpeed: speed, history: history)
        run = model
        model.start()
    }
}

private struct SegmentLabel: View {
    let segment: CourseSegment
    let courseDistance: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(segment.name ?? "Custom")
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var detail: String {
        let distance = RunFormatting.miles(segment.distanceMeters, decimals: 1)
        guard segment.startMeters > 0 || segment.endMeters < courseDistance else { return distance }
        let range =
            "mi \(RunFormatting.mileNumber(segment.startMeters))–\(RunFormatting.mileNumber(segment.endMeters))"
        return "\(distance) · \(range)"
    }
}

/// A large mph value with −1, −0.1, +0.1, +1 buttons, matching the treadmill's knob and jump buttons.
struct SpeedControl: View {
    let speed: Speed
    var isLarge = false
    let onChange: (Speed) -> Void

    var body: some View {
        HStack(spacing: 8) {
            stepButton("−1", steps: -10)
            stepButton("−", steps: -1)
            Text(String(format: "%.1f", speed.mph))
                .font(.system(size: isLarge ? 44 : 34, weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: isLarge ? 96 : 80)
                .accessibilityLabel("Speed \(RunFormatting.speed(speed))")
            stepButton("+", steps: 1)
            stepButton("+1", steps: 10)
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) {
            Text("mph").font(.caption).foregroundStyle(.secondary).offset(y: isLarge ? 20 : 16)
        }
        .padding(.bottom, 12)
    }

    private func stepButton(_ title: String, steps: Int) -> some View {
        Button(title) { onChange(speed.stepped(by: steps)) }
            .font(.system(size: isLarge ? 24 : 20, weight: .semibold, design: .rounded))
            .frame(minWidth: isLarge ? 52 : 44, minHeight: isLarge ? 60 : 44)
            .buttonStyle(.bordered)
            .accessibilityIdentifier("speed-step-\(steps)")
            .accessibilityLabel(
                steps > 0 ? "Increase speed \(Double(steps) / 10) mph" : "Decrease speed \(Double(-steps) / 10) mph")
    }
}
