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
        // Services
        .library(name: "PowerService", targets: ["PowerService"]),
        // Modules
        .library(name: "SampleModule", targets: ["SampleModule"]),
        .library(name: "KeepAwake", targets: ["KeepAwake"]),
    ],
    targets: [
        // Core: the module contract and the shared parts every feature uses.
        .target(name: "TrebleCore", path: "Sources/TrebleCore"),

        // Shell: menu bar, panel, Settings, onboarding. Knows Core, never Modules.
        .target(name: "TrebleShell", dependencies: ["TrebleCore"], path: "Sources/TrebleShell"),

        // Services: shared system plumbing, used by several modules.
        .target(name: "PowerService", dependencies: ["TrebleCore"], path: "Sources/Services/PowerService"),

        // Modules: one target each, depending only on Core and the Services they list.
        .target(name: "SampleModule", dependencies: ["TrebleCore"], path: "Sources/Modules/SampleModule"),
        .target(name: "KeepAwake", dependencies: ["TrebleCore", "PowerService"], path: "Sources/Modules/KeepAwake"),

        .testTarget(
            name: "TrebleCoreTests",
            dependencies: ["TrebleCore"],
            path: "Tests/TrebleCoreTests"
        ),
        .testTarget(
            name: "KeepAwakeTests",
            dependencies: ["KeepAwake", "PowerService", "TrebleCore"],
            path: "Tests/KeepAwakeTests"
        ),
    ]
)
