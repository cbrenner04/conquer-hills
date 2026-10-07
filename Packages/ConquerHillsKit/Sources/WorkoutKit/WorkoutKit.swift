import CourseKit

/// Workout engine: progress tracking, incline transitions, pause and resume.
///
/// Placeholder until spec 03 defines the engine.
public enum WorkoutKit {
    /// Identifies the module; shown by the app's placeholder screen to prove the package is linked.
    public static let moduleName = "WorkoutKit"

    /// The modules this one is built on, proving the `CourseKit` dependency is wired.
    public static let dependencies = [CourseKit.moduleName]
}
