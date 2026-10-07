import Testing

@testable import WorkoutKit

@Test func dependsOnCourseKit() {
    #expect(WorkoutKit.dependencies == ["CourseKit"])
}
