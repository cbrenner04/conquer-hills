// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ConquerHillsKit",
    platforms: [
        .iOS(.v26),
        // macOS is supported so `swift test` runs natively on the development Mac.
        .macOS(.v26),
    ],
    products: [
        .library(name: "CourseKit", targets: ["CourseKit"]),
        .library(name: "WorkoutKit", targets: ["WorkoutKit"]),
    ],
    targets: [
        .target(name: "CourseKit"),
        .target(name: "WorkoutKit", dependencies: ["CourseKit"]),
        .testTarget(name: "CourseKitTests", dependencies: ["CourseKit"]),
        .testTarget(name: "WorkoutKitTests", dependencies: ["WorkoutKit"]),
    ],
    swiftLanguageModes: [.v6]
)
