import CourseKit
import SwiftUI
import WorkoutKit

/// The first screen: every bundled course.
struct CourseListView: View {
    let courses: [Course]
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(courses) { course in
                        NavigationLink(value: course.id) {
                            CourseRow(course: course)
                        }
                    }
                } header: {
                    header
                }
            }
            .navigationTitle("Courses")
            .toolbarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { id in
                if let course = courses.first(where: { $0.id == id }) {
                    RunSetupView(course: course, onDone: { path.removeAll() })
                }
            }
            .overlay {
                if courses.isEmpty {
                    ContentUnavailableView(
                        "No courses", systemImage: "mountain.2", description: Text("No course files could be loaded."))
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Conquer Hills")
                .font(.largeTitle.bold())
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .textCase(nil)
    }
}

private struct CourseRow: View {
    let course: Course

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(course.name)
                .font(.headline)
            Text(
                "\(course.edition) · \(RunFormatting.miles(course.distanceMeters)) · ↑ \(RunFormatting.feet(course.stats.elevationGainMeters))"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
