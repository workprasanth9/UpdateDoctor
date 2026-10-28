// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "UpdateDoctor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "updatedoctor", targets: ["updatedoctor"]),
        .library(name: "UpdateDoctorKit", targets: ["UpdateDoctorKit"]),
        .executable(name: "UpdateDoctorApp", targets: ["UpdateDoctorApp"]),
    ],
    targets: [
        .target(name: "UpdateDoctorKit"),
        .executableTarget(name: "updatedoctor", dependencies: ["UpdateDoctorKit"]),
        // Menu bar state and status mapping, kept free of AppKit so it can be tested.
        .target(name: "UpdateDoctorMenuCore", dependencies: ["UpdateDoctorKit"]),
        // UpdateDoctor.app, packaged by Scripts/build-app.sh.
        .executableTarget(name: "UpdateDoctorApp", dependencies: ["UpdateDoctorKit", "UpdateDoctorMenuCore"]),
        // Same fixture tests, runnable without XCTest: `swift run fixture-tests`.
        .executableTarget(
            name: "fixture-tests",
            dependencies: ["UpdateDoctorKit", "UpdateDoctorMenuCore"],
            path: "LocalTestRunner",
            resources: [.copy("Fixtures")],
            swiftSettings: [.unsafeFlags(["-enable-testing"])]
        ),
        .testTarget(
            name: "UpdateDoctorKitTests",
            dependencies: ["UpdateDoctorKit", "UpdateDoctorMenuCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
