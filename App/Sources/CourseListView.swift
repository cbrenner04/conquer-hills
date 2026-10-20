import CourseKit
import SwiftUI
import WorkoutKit

/// The first screen: every bundled course, grouped by distance or region (`CourseGrouping`), with search.
struct CourseListView: View {
    let courses: [Course]
    @State private var path: [String] = []
    @State private var query = ""
    @AppStorage("courseListGrouping") private var grouping = CourseGroupingMode.distance

    private var sections: [CourseSection] { CourseGrouping.sections(courses, by: grouping, matching: query) }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Picker("Group by", selection: $grouping) {
                        ForEach(CourseGroupingMode.allCases, id: \.self) { mode in
                            Text(mode.title)
                                .tag(mode)
                                .accessibilityIdentifier("grouping-\(mode.rawValue)")
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } header: {
                    header
                }
                ForEach(sections) { section in
                    Section(section.title) {
                        ForEach(section.courses) { course in
                            NavigationLink(value: course.id) {
                                CourseRow(course: course)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search courses")
            .navigationTitle("Courses")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        AboutView(courses: courses)
                    } label: {
                        Label("About", systemImage: "info.circle")
                    }
                    .accessibilityIdentifier("about")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("settings")
                    NavigationLink {
                        HistoryListView()
                    } label: {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }
                    .accessibilityIdentifier("history")
                }
            }
            .navigationDestination(for: String.self) { id in
                if let course = courses.first(where: { $0.id == id }) {
                    CourseView(course: course, onDone: { path.removeAll() })
                }
            }
            .overlay {
                if courses.isEmpty {
                    ContentUnavailableView(
                        "No courses", systemImage: "mountain.2", description: Text("No course files could be loaded."))
                } else if sections.isEmpty {
                    ContentUnavailableView(
                        "No courses match", systemImage: "magnifyingglass", description: Text("Try a course or a city.")
                    )
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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(course.name)
                    .font(.headline)
                Text(
                    "\(CourseRegion.city(of: course.location)) · \(RunFormatting.miles(course.distanceMeters)) · ↑ \(RunFormatting.feet(course.stats.elevationGainMeters))"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer()
            ProfileSparkline(course: course)
        }
        .padding(.vertical, 4)
    }
}
