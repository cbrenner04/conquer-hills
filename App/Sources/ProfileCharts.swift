import Charts
import CourseKit
import SwiftUI
import WorkoutKit

/// A point for elevation charts, in display units.
private struct ProfilePoint: Identifiable {
    let id: Int
    let miles: Double
    let feet: Double

    static func points(_ samples: [ElevationSample]) -> [ProfilePoint] {
        samples.enumerated().map {
            ProfilePoint(
                id: $0.offset, miles: $0.element.distanceMeters / RunFormatting.metersPerMile,
                feet: $0.element.elevationMeters * RunFormatting.feetPerMeter)
        }
    }
}

/// Lower and upper elevation bounds (feet) with some headroom, so flat courses don't look like walls.
private func feetDomain(_ samples: [ElevationSample]) -> ClosedRange<Double> {
    let feet = samples.map { $0.elevationMeters * RunFormatting.feetPerMeter }
    let low = feet.min() ?? 0
    let high = feet.max() ?? 1
    let pad = max((high - low) * 0.15, 15)
    return (low - pad)...(high + pad)
}

/// A tiny whole-course elevation shape for course list rows.
struct ProfileSparkline: View {
    let course: Course

    var body: some View {
        let samples = ElevationChartData.downsample(course.elevationProfile, maximumPoints: 60)
        let domain = feetDomain(samples)
        Chart(ProfilePoint.points(samples)) { point in
            AreaMark(
                x: .value("mi", point.miles), yStart: .value("ft", domain.lowerBound), yEnd: .value("ft", point.feet)
            )
            .foregroundStyle(.tint.opacity(0.35))
            LineMark(x: .value("mi", point.miles), y: .value("ft", point.feet))
                .foregroundStyle(.tint)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: domain)
        .frame(width: 64, height: 28)
        .accessibilityHidden(true)
    }
}

/// The course's elevation profile with the selected segment highlighted and its ends labelled.
struct CourseProfileChart: View {
    let course: Course
    let segment: CourseSegment

    var body: some View {
        let all = ElevationChartData.downsample(course.elevationProfile, maximumPoints: 400)
        let selected = ElevationChartData.downsample(
            ElevationChartData.slice(course.elevationProfile, from: segment.startMeters, to: segment.endMeters),
            maximumPoints: 400)
        let domain = feetDomain(all)
        let isWhole = segment.startMeters <= 0 && segment.endMeters >= course.distanceMeters
        Chart {
            ForEach(ProfilePoint.points(all)) { point in
                AreaMark(
                    x: .value("mi", point.miles), yStart: .value("ft", domain.lowerBound),
                    yEnd: .value("ft", point.feet), series: .value("Part", "Course")
                )
                .foregroundStyle(Color.secondary.opacity(isWhole ? 0 : 0.25))
            }
            ForEach(ProfilePoint.points(selected)) { point in
                AreaMark(
                    x: .value("mi", point.miles), yStart: .value("ft", domain.lowerBound),
                    yEnd: .value("ft", point.feet), series: .value("Part", "Segment")
                )
                .foregroundStyle(.tint.opacity(0.45))
                LineMark(x: .value("mi", point.miles), y: .value("ft", point.feet), series: .value("Part", "Line"))
                    .foregroundStyle(.tint)
            }
            if !isWhole {
                boundary(segment.startMeters)
                boundary(segment.endMeters)
            }
        }
        .chartYScale(domain: domain)
        .chartXScale(domain: 0...(course.distanceMeters / RunFormatting.metersPerMile))
        .chartXAxisLabel("mi")
        .chartYAxisLabel("ft")
        .frame(height: 180)
        .accessibilityLabel(
            "Elevation profile, \(RunFormatting.feet(course.stats.minimumElevationMeters)) to \(RunFormatting.feet(course.stats.maximumElevationMeters))"
        )
    }

    private func boundary(_ meters: Double) -> some ChartContent {
        RuleMark(x: .value("mi", meters / RunFormatting.metersPerMile))
            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .foregroundStyle(.tint)
            .annotation(position: .top, spacing: 2) {
                Text("mi \(RunFormatting.mileNumber(meters))")
                    .font(.caption2.bold())
                    .foregroundStyle(.tint)
            }
    }
}

/// A thin, unlabelled strip of the run's elevation with a marker at the runner's position.
struct RunProfileStrip: View {
    /// The segment's elevation samples, in course positions.
    let samples: [ElevationSample]
    let positionMeters: Double

    var body: some View {
        let domain = feetDomain(samples)
        let positionMiles = positionMeters / RunFormatting.metersPerMile
        Chart {
            ForEach(ProfilePoint.points(samples)) { point in
                AreaMark(
                    x: .value("mi", point.miles), yStart: .value("ft", domain.lowerBound),
                    yEnd: .value("ft", point.feet)
                )
                .foregroundStyle(Color.white.opacity(0.18))
            }
            RuleMark(x: .value("mi", positionMiles))
                .foregroundStyle(.white)
                .lineStyle(StrokeStyle(lineWidth: 2))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: domain)
        .chartXScale(
            domain: (samples.first?.distanceMeters ?? 0)
                / RunFormatting.metersPerMile...(samples.last?.distanceMeters ?? 1)
                / RunFormatting.metersPerMile
        )
        .frame(height: 40)
        .accessibilityHidden(true)
    }
}
