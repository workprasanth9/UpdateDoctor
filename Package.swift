// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "UpdateDoctor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "updatedoctor", targets: ["updatedoctor"]),
        .library(name: "UpdateDoctorKit", targets: ["UpdateDoctorKit"]),
    ],
    targets: [
        .target(name: "UpdateDoctorKit"),
        .executableTarget(name: "updatedoctor", dependencies: ["UpdateDoctorKit"]),
        // Same fixture tests, runnable without XCTest: `swift run fixture-tests`.
        .executableTarget(
            name: "fixture-tests",
            dependencies: ["UpdateDoctorKit"],
            path: "LocalTestRunner",
            resources: [.copy("Fixtures")],
            swiftSettings: [.unsafeFlags(["-enable-testing"])]
        ),
        .testTarget(
            name: "UpdateDoctorKitTests",
            dependencies: ["UpdateDoctorKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
