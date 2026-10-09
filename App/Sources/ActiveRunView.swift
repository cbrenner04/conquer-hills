import SwiftUI
import WorkoutKit

/// The run screen, readable from a metre away: current incline biggest, then the next change, progress, speed,
/// and Pause / End. Shows the summary when the run is over.
struct ActiveRunView: View {
    let model: RunModel
    let onDone: () -> Void
    let onRunAgain: () -> Void

    @State private var confirmingEnd = false
    @State private var flashOpacity = 0.0

    private static let upColor = Color.orange
    private static let downColor = Color.cyan

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if model.isOver {
                SummaryView(
                    record: model.workout.record, isSaved: model.savedEntryID != nil,
                    onDelete: model.deleteSavedRun, onDone: finish(onDone), onRunAgain: finish(onRunAgain))
            } else {
                runContent
                flash
                if model.snapshot.state == .paused {
                    pausedOverlay
                }
                if let countdown = model.snapshot.countdownRemaining {
                    countdownOverlay(countdown)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.impact(weight: .heavy), trigger: model.changeCount)
        .onChange(of: model.changeCount) {
            flashOpacity = 0.6
            withAnimation(.easeOut(duration: 1.2)) { flashOpacity = 0 }
        }
        .confirmationDialog("End run?", isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button("End", role: .destructive) { model.end() }
            Button("Keep running", role: .cancel) {}
        }
    }

    private func finish(_ action: @escaping () -> Void) -> () -> Void {
        {
            model.stop()
            action()
        }
    }

    // MARK: Run content

    private var snapshot: WorkoutSnapshot { model.snapshot }

    private var runContent: some View {
        VStack(spacing: 0) {
            Text("\(model.courseName) · \(model.segmentName)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 8)

            Spacer(minLength: 8)
            currentIncline
            Spacer(minLength: 8)
            nextChange
            Spacer(minLength: 8)
            if model.profileSamples.count > 1 {
                RunProfileStrip(samples: model.profileSamples, positionMeters: snapshot.coursePositionMeters)
                    .padding(.bottom, 6)
            }
            progress
            Spacer(minLength: 16)
            SpeedControl(speed: snapshot.speed, isLarge: true) { newSpeed in
                let steps = Int(((newSpeed.mph - snapshot.speed.mph) / Speed.stepMph).rounded())
                model.changeSpeed(bySteps: steps)
            }
            Spacer(minLength: 16)
            controls
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .foregroundStyle(.white)
    }

    private var currentIncline: some View {
        VStack(spacing: 4) {
            Text(RunFormatting.incline(snapshot.currentInclinePercent))
                .font(.system(size: 112, weight: .heavy, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .accessibilityLabel("Incline \(RunFormatting.incline(snapshot.currentInclinePercent))")
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let change = model.lastChange, context.date.timeIntervalSince(change.at) < 6 {
                    Text("\(change.isUp ? "▲" : "▼") from \(RunFormatting.incline(change.fromPercent))")
                        .font(.title2.bold())
                        .foregroundStyle(change.isUp ? Self.upColor : Self.downColor)
                } else {
                    Text(" ").font(.title2)
                }
            }
        }
    }

    @ViewBuilder
    private var nextChange: some View {
        if let next = snapshot.nextChange {
            let isUp = next.inclinePercent > snapshot.currentInclinePercent
            let highlighted = model.warningActive
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Text("NEXT")
                        .font(.headline)
                        .foregroundStyle(highlighted ? .black : .secondary)
                    Text("\(isUp ? "▲" : "▼") \(RunFormatting.incline(next.inclinePercent))")
                        .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    Text("in \(RunFormatting.duration(next.timeRemaining))")
                        .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                }
                Text(RunFormatting.miles(next.distanceMeters))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(highlighted ? .black : .secondary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .foregroundStyle(highlighted ? .black : .white)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(highlighted ? (isUp ? Self.upColor : Self.downColor) : Color.white.opacity(0.08)))
        } else {
            Text("No more changes")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.vertical, 10)
        }
    }

    private var progress: some View {
        let segment = model.workout.profile.segment
        return VStack(spacing: 6) {
            ProgressView(value: snapshot.fractionComplete)
                .tint(.white)
            HStack {
                Text(
                    "\(RunFormatting.miles(snapshot.distanceMeters)) of \(RunFormatting.miles(segment.distanceMeters))"
                )
                Spacer()
                Text(RunFormatting.duration(snapshot.activeElapsed))
            }
            .font(.title3.monospacedDigit())
            if segment.startMeters > 0 {
                Text("course mi \(RunFormatting.mileNumber(snapshot.coursePositionMeters, decimals: 2))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button {
                snapshot.state == .paused ? model.resume() : model.pause()
            } label: {
                Text(snapshot.state == .paused ? "Resume" : "Pause")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
            .buttonStyle(.borderedProminent)
            .disabled(snapshot.state == .countingDown)
            .accessibilityIdentifier("pause-resume")

            Button {
                confirmingEnd = true
            } label: {
                Text("End")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(snapshot.state == .countingDown)
            .accessibilityIdentifier("end")
        }
    }

    // MARK: Overlays

    private var flash: some View {
        (model.lastChange?.isUp ?? true ? Self.upColor : Self.downColor)
            .opacity(flashOpacity)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    private var pausedOverlay: some View {
        VStack(spacing: 24) {
            Text("Paused")
                .font(.system(size: 56, weight: .heavy, design: .rounded))
            Button {
                model.resume()
            } label: {
                Text("Resume")
                    .font(.title.bold())
                    .frame(maxWidth: .infinity, minHeight: 64)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("overlay-resume")
            Button("End run", role: .destructive) { confirmingEnd = true }
                .font(.title3)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.85))
        .foregroundStyle(.white)
    }

    private func countdownOverlay(_ seconds: Int) -> some View {
        VStack(spacing: 16) {
            Text("Set incline to \(RunFormatting.incline(snapshot.currentInclinePercent))")
                .font(.title2.bold())
            Text("\(seconds)")
                .font(.system(size: 160, weight: .heavy, design: .rounded).monospacedDigit())
            Text("Start the treadmill on “Go”")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .foregroundStyle(.white)
    }
}
