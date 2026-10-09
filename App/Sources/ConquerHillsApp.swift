import CourseKit
import SwiftUI

@main
struct ConquerHillsApp: App {
    private let courses = CourseLibrary.loadBundled()
    @State private var history = RunHistoryModel()

    var body: some Scene {
        WindowGroup {
            CourseListView(courses: courses)
                .environment(history)
        }
    }
}

/// The courses bundled with the app.
enum CourseLibrary {
    /// Loads every valid course from `Courses/` in the app bundle. Invalid files are left out (CourseLoader logs
    /// why). Development-only courses such as Test Hills appear only in Debug builds.
    static func loadBundled() -> [Course] {
        guard let directory = Bundle.main.url(forResource: "Courses", withExtension: nil) else { return [] }
        let courses = CourseLoader.loadAll(in: directory).courses
        #if DEBUG
            return courses
        #else
            return courses.filter { !$0.isDevelopmentOnly }
        #endif
    }
}
