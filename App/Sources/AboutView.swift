import CourseKit
import SwiftUI

/// What the app is, how to use it safely, and credit for the data it's built on.
struct AboutView: View {
    let courses: [Course]

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Conquer Hills").font(.title2.bold())
                    Text("Version \(version)").font(.subheadline).foregroundStyle(.secondary)
                    Text(
                        "Run a real race course's hills on a treadmill. Enter your speed, and the app follows your position on the course and tells you when to change the incline. It doesn't connect to or control the treadmill."
                    )
                }
                .padding(.vertical, 4)
            }

            Section("Safety") {
                Text(
                    "Incline prompts approximate the course. Get to know your treadmill's controls before you start, and only change settings when it's safe to."
                )
            }

            Section("Data credits") {
                Link(
                    "Route data © OpenStreetMap contributors (ODbL)",
                    destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                Text(
                    "Japan elevation data: Geospatial Information Authority of Japan (国土地理院), processed by Conquer Hills."
                )
                Text("U.S. elevation data: U.S. Geological Survey 3D Elevation Program, processed by Conquer Hills.")
                Text(
                    "Course names are used descriptively. Conquer Hills isn't affiliated with or endorsed by any race organiser."
                )
            }
            .font(.subheadline)

            Section("Courses") {
                ForEach(courses) { course in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(course.name) \(course.edition)").font(.headline)
                        if let attribution = course.source.attribution {
                            Text(attribution).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("About")
        .toolbarTitleDisplayMode(.inline)
    }
}
