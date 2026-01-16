// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MachScope",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "machscope", targets: ["MachScope"]),
        .library(name: "MachOKit", targets: ["MachOKit"]),
        .library(name: "Disassembler", targets: ["Disassembler"]),
        .library(name: "DebuggerCore", targets: ["DebuggerCore"]),
        .library(name: "Decompiler", targets: ["Decompiler"]),
        .library(name: "Plugins", targets: ["Plugins"])
    ],
    targets: [
        // Core Mach-O parsing library
        .target(
            name: "MachOKit",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),

        // ARM64 instruction decoder
        .target(
            name: "Disassembler",
            dependencies: ["MachOKit"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),

        // Process debugging (optional - requires entitlements)
        .target(
            name: "DebuggerCore",
            dependencies: ["MachOKit", "Disassembler"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),

        // Basic decompiler for pseudo-code generation
        .target(
            name: "Decompiler",
            dependencies: ["MachOKit", "Disassembler"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),

        // Plugin system for extensibility
        .target(
            name: "Plugins",
            dependencies: ["MachOKit"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),

        // CLI executable
        .executableTarget(
            name: "MachScope",
            dependencies: ["MachOKit", "Disassembler", "DebuggerCore", "Decompiler", "Plugins"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),

        // Test targets
        .testTarget(
            name: "MachOKitTests",
            dependencies: ["MachOKit"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "DisassemblerTests",
            dependencies: ["Disassembler"]
        ),
        .testTarget(
            name: "DebuggerCoreTests",
            dependencies: ["DebuggerCore"]
        ),
        .testTarget(
            name: "IntegrationTests",
            dependencies: ["MachOKit", "Disassembler", "DebuggerCore"]
        )
    ]
)
