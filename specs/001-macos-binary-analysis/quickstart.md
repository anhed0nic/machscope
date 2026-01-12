# Quickstart Guide: MachScope Development

**Feature Branch**: `001-macos-binary-analysis`
**Created**: 2026-01-12

## Prerequisites

- macOS Tahoe 26.0 or later
- Apple Silicon Mac (arm64)
- Xcode 16.0+ with Command Line Tools
- Swift 6.2.3+

Verify your environment:

```bash
# Check macOS version
sw_vers

# Check Swift version
swift --version
# Expected: Swift version 6.2.3 or higher

# Check Xcode
xcode-select -p
# Expected: /Applications/Xcode.app/Contents/Developer
```

---

## Project Setup

### 1. Clone and Build

```bash
# Clone repository
git clone <repository-url>
cd MachScope

# Build the project
swift build

# Run tests
swift test

# Build release version
swift build -c release
```

### 2. Package Structure

```
MachScope/
├── Package.swift           # Swift Package manifest
├── Sources/
│   ├── MachOKit/          # Core parsing library
│   ├── Disassembler/      # ARM64 decoder
│   ├── DebuggerCore/      # Process debugging
│   └── MachScope/         # CLI executable
├── Tests/
│   ├── MachOKitTests/
│   ├── DisassemblerTests/
│   └── IntegrationTests/
└── Resources/
    └── MachScope.entitlements
```

### 3. Package.swift Configuration

```swift
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
        .library(name: "DebuggerCore", targets: ["DebuggerCore"])
    ],
    targets: [
        // Libraries
        .target(
            name: "MachOKit",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "Disassembler",
            dependencies: ["MachOKit"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "DebuggerCore",
            dependencies: ["MachOKit", "Disassembler"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),

        // Executable
        .executableTarget(
            name: "MachScope",
            dependencies: ["MachOKit", "Disassembler", "DebuggerCore"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),

        // Tests
        .testTarget(name: "MachOKitTests", dependencies: ["MachOKit"]),
        .testTarget(name: "DisassemblerTests", dependencies: ["Disassembler"]),
        .testTarget(name: "DebuggerCoreTests", dependencies: ["DebuggerCore"]),
        .testTarget(name: "IntegrationTests", dependencies: ["MachScope"])
    ]
)
```

---

## Development Workflow

### Running the CLI

```bash
# From build directory
swift run machscope parse /bin/ls

# With options
swift run machscope parse /bin/ls --symbols --json

# Disassemble a function
swift run machscope disasm /bin/ls --function _main

# Check permissions
swift run machscope check-permissions
```

### Running Tests

```bash
# All tests
swift test

# Specific test target
swift test --filter MachOKitTests

# Specific test
swift test --filter MachOKitTests.HeaderTests/testValidMachOHeader

# With verbose output
swift test -v
```

### Code Style

```bash
# Format code (requires swift-format)
swift-format -i -r Sources/ Tests/

# Lint
swift-format lint -r Sources/ Tests/
```

---

## Module Development

### MachOKit (Core Parsing)

Key entry point: `MachOBinary.swift`

```swift
import MachOKit

// Parse a binary
let binary = try MachOBinary(path: "/path/to/binary")

// Access header
print(binary.header.cpuType)        // .arm64
print(binary.header.fileType)       // .execute

// Access segments
for segment in binary.segments {
    print("\(segment.name): \(segment.vmAddress)")
}

// Lazy load symbols
if let symbols = binary.symbols {
    for symbol in symbols {
        print("\(symbol.name): \(symbol.address)")
    }
}
```

### Disassembler (ARM64 Decoder)

Key entry point: `ARM64Disassembler.swift`

```swift
import Disassembler
import MachOKit

// Create disassembler with binary context
let binary = try MachOBinary(path: "/path/to/binary")
let disasm = ARM64Disassembler(symbolResolver: binary)

// Disassemble raw bytes
let instruction = disasm.decode(0x94000013, at: 0x100003f54)
print(instruction.mnemonic)   // "bl"
print(instruction.operands)   // "_helper_function"

// Disassemble a function
if let mainSymbol = binary.symbol(named: "_main") {
    let instructions = try disasm.disassembleFunction(at: mainSymbol.address)
    for inst in instructions {
        print("\(inst.address): \(inst.mnemonic) \(inst.operands)")
    }
}
```

### DebuggerCore (Process Debugging)

Key entry point: `Debugger.swift`

```swift
import DebuggerCore

// Check permissions first
let checker = PermissionChecker()
guard checker.canDebug else {
    print(checker.guidance)
    return
}

// Attach to process
let debugger = try Debugger(pid: 12345)

// Set breakpoint
let bp = try debugger.setBreakpoint(at: 0x100003f40)
print("Breakpoint \(bp.id) set")

// Continue and wait for stop
try debugger.continue()
let stopReason = try await debugger.waitForStop()

// Read registers
let registers = try debugger.readRegisters()
print("PC: \(registers.pc)")

// Single step
try debugger.step()

// Detach
try debugger.detach()
```

---

## Debugging the Debugger

To debug MachScope itself (meta-debugging):

### 1. Code Signing for Development

Create `Debug.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.debugger</key>
    <true/>
    <key>com.apple.security.get-task-allow</key>
    <true/>
</dict>
</plist>
```

### 2. Sign the Binary

```bash
# Build
swift build

# Sign with entitlements
codesign --force --sign - --entitlements Debug.entitlements \
    .build/debug/machscope
```

### 3. Enable Developer Tools

1. Open **System Settings** > **Privacy & Security** > **Developer Tools**
2. Enable **Terminal** (or Xcode)
3. Restart Terminal

---

## Test Fixtures

### Creating Test Binaries

```bash
# Simple test binary
cat > /tmp/test.c << 'EOF'
int helper(int x) { return x * 2; }
int main(int argc, char **argv) { return helper(argc); }
EOF

# Compile for arm64
clang -arch arm64 -o Tests/Fixtures/simple_arm64 /tmp/test.c

# Create Fat binary
clang -arch arm64 -arch x86_64 -o Tests/Fixtures/fat_binary /tmp/test.c

# Sign with get-task-allow (for debugger tests)
codesign --force --sign - --entitlements Debug.entitlements \
    Tests/Fixtures/simple_arm64
```

### Creating Malformed Binaries

```bash
# Truncated header
head -c 16 Tests/Fixtures/simple_arm64 > Tests/Fixtures/malformed/truncated

# Invalid magic
echo -n "XXXX" > Tests/Fixtures/malformed/invalid_magic
```

---

## Common Tasks

### Adding a New Load Command

1. Add case to `LoadCommandType` enum in `LoadCommands/LoadCommand.swift`
2. Create payload struct if needed
3. Add parsing in `LoadCommand.parse()`
4. Add tests in `MachOKitTests/LoadCommandTests.swift`

### Adding a New Instruction

1. Identify encoding pattern in ARM ARM
2. Add decode logic in appropriate file under `Decoder/`
3. Add formatter in `Formatter/InstructionFormatter.swift`
4. Add test case with known encoding

### Adding a Debugger Command

1. Add command enum case in `Commands/DebugCommand.swift`
2. Implement handler in `Debugger.swift`
3. Add to interactive command parser
4. Document in `contracts/cli-interface.md`

---

## Troubleshooting

### Build Errors

**Swift version mismatch**:
```
error: package requires minimum Swift tools version 6.2
```
Solution: Update Xcode or use `xcrun --toolchain` to select correct Swift.

**Missing concurrency features**:
```
error: 'Sendable' is only available in Swift 6.0 or newer
```
Solution: Ensure Package.swift specifies `.macOS(.v26)` platform.

### Runtime Errors

**Permission denied (debugging)**:
```
Error: Cannot attach to process: permission denied
```
Solution: Run `machscope check-permissions` and follow guidance.

**Invalid Mach-O**:
```
Error: Not a valid Mach-O binary: invalid magic number
```
Solution: Verify file is actually a Mach-O binary with `file <path>`.

### Test Failures

**Fixture not found**:
```
XCTFail: Test fixture not found at Tests/Fixtures/...
```
Solution: Run fixture creation commands above.

**Flaky debugger tests**:
Debugger tests may be timing-sensitive. Increase timeouts or mark as integration tests.

---

## Resources

### Documentation
- [plan.md](./plan.md) - Implementation plan
- [data-model.md](./data-model.md) - Entity definitions
- [contracts/cli-interface.md](./contracts/cli-interface.md) - CLI specification
- [research.md](./research.md) - Technical research

### External References
- [Apple Mach-O Reference](https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/MachOTopics/)
- [ARM A64 ISA](https://developer.arm.com/documentation/ddi0602/latest)
- [Swift ABI](https://github.com/apple/swift/tree/main/docs/ABI)

---

**Document Version**: 1.0
**Last Updated**: 2026-01-12
