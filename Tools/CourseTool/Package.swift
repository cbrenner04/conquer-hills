// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CourseTool",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "course-tool", targets: ["course-tool"])
    ],
    dependencies: [
        .package(path: "../../Packages/ConquerHillsKit")
    ],
    targets: [
        // Pure, offline pipeline logic: geometry, calibration, cleaning, smoothing, intervals, report.
        .target(
            name: "CourseToolCore",
            dependencies: [.product(name: "CourseKit", package: "ConquerHillsKit")]
        ),
        // Command-line entry point and the network clients (router, Overpass, elevation services).
        .executableTarget(name: "course-tool", dependencies: ["CourseToolCore"]),
        .testTarget(name: "CourseToolCoreTests", dependencies: ["CourseToolCore"]),
    ],
    swiftLanguageModes: [.v6]
)
