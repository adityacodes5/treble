// swift-tools-version: 6.0
//
// TrebleKit holds almost all of Treble's code, split into targets so the
// compiler keeps features apart. Dependency rules (checked by
// scripts/check-isolation.sh):
//
//   App ──► Modules ──► Services ──► TrebleCore
//   App ──► TrebleShell ──► TrebleCore
//
//   ✗ Modules never import other Modules, Services never import Modules,
//     TrebleCore imports nothing of ours, the Shell never imports Modules.

import PackageDescription

let package = Package(
    name: "TrebleKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TrebleCore", targets: ["TrebleCore"]),
        .library(name: "TrebleShell", targets: ["TrebleShell"]),
        // Modules
        .library(name: "SampleModule", targets: ["SampleModule"]),
    ],
    targets: [
        // Core: the module contract and the shared parts every feature uses.
        .target(name: "TrebleCore", path: "Sources/TrebleCore"),

        // Shell: menu bar, panel, Settings, onboarding. Knows Core, never Modules.
        .target(name: "TrebleShell", dependencies: ["TrebleCore"], path: "Sources/TrebleShell"),

        // Modules: one target each, depending only on Core (and Services, later).
        .target(name: "SampleModule", dependencies: ["TrebleCore"], path: "Sources/Modules/SampleModule"),

        .testTarget(
            name: "TrebleCoreTests",
            dependencies: ["TrebleCore"],
            path: "Tests/TrebleCoreTests"
        ),
    ]
)
