// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PassportKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "SpecKit", targets: ["SpecKit"]),
        .library(name: "PhotoAnalysis", targets: ["PhotoAnalysis"]),
        .library(name: "PhotoPipeline", targets: ["PhotoPipeline"]),
    ],
    targets: [
        .target(name: "SpecKit"),
        .target(name: "PhotoAnalysis", dependencies: ["SpecKit"]),
        .target(name: "PhotoPipeline", dependencies: ["PhotoAnalysis", "SpecKit"]),
        // Test-only helper: locates the repo root so fixture/spec files load by path.
        .target(name: "TestSupport"),
        .testTarget(name: "SpecKitTests", dependencies: ["SpecKit", "TestSupport"]),
        .testTarget(name: "PlannerTests", dependencies: ["PhotoPipeline", "SpecKit", "TestSupport"]),
        .testTarget(name: "FixtureTests", dependencies: ["PhotoPipeline", "SpecKit", "TestSupport"]),
    ],
    swiftLanguageModes: [.v6]
)
