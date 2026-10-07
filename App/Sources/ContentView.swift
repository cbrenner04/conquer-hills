import CourseKit
import SwiftUI
import WorkoutKit

/// Placeholder screen until the first real UI arrives in spec 04.
struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Conquer Hills")
                .font(.largeTitle.bold())
            Text("Linked: \(CourseKit.moduleName), \(WorkoutKit.moduleName)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
