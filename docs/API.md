# API Reference

Use MachScope modules as libraries in your own Swift projects.

## Adding MachScope as a Dependency

### Package.swift

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MyApp",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "/path/to/MachScope")
        // Or from git:
        // .package(url: "https://github.com/sadopc/machscope.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "MyApp",
            dependencies: [
                .product(name: "MachOKit", package: "MachScope"),
                .product(name: "Disassembler", package: "MachScope"),
                .product(name: "DebuggerCore", package: "MachScope"),
            ]
        )
    ]
)
```

---

## MachOKit Module

Import:
```swift
import MachOKit
```

### MachOBinary

Main entry point for parsing Mach-O files.

#### Initialization

```swift
// Parse a binary file
let binary = try MachOBinary(path: "/bin/ls")

// Parse specific architecture from Universal binary
let binary = try MachOBinary(path: "/path/to/fat", architecture: .x86_64)
```

#### Properties

```swift
// File information
binary.path          // String - File path
binary.fileSize      // UInt64 - File size in bytes
binary.isMemoryMapped // Bool - Using mmap?

// Parsed structures
binary.header        // MachHeader
binary.loadCommands  // [LoadCommand]
binary.segments      // [Segment]
binary.symbols       // [Symbol]? - Lazy loaded
binary.dylibDependencies // [DylibCommand]
```

#### Methods

```swift
// Segment access
let text = binary.segment(named: "__TEXT")
let segment = binary.segment(containing: 0x100003f40)

// Section access
let section = binary.section(segment: "__TEXT", section: "__text")
let allSections = binary.allSections

// Symbol lookup
let main = binary.symbol(named: "_main")
let symbol = binary.symbol(at: 0x100003f40)

// Data access
let data = try binary.readSectionData(section)
let segmentData = try binary.readSegmentData(segment)

// Code signature
let signature = try binary.parseCodeSignature()
let isSigned = binary.isSigned

// Entry point and metadata
let entry = binary.entryPoint    // EntryPointCommand?
let uuid = binary.uuid           // UUID?
let version = binary.buildVersion // BuildVersionCommand?
```

### MachHeader

```swift
let header = binary.header

header.magic           // UInt32 - Magic number
header.cpuType         // CPUType - CPU architecture
header.cpuSubtype      // CPUSubtype - CPU variant
header.fileType        // FileType - Executable, dylib, etc.
header.numberOfCommands // UInt32
header.sizeOfCommands  // UInt32
header.flags           // MachHeaderFlags
```

### CPUType

```swift
enum CPUType {
    case arm64
    case arm64e
    case x86_64
    case arm
    case x86
}

// Check architecture
if header.cpuType == .arm64 { ... }
```

### FileType

```swift
enum FileType {
    case execute    // Executable
    case dylib      // Dynamic library
    case bundle     // Loadable bundle
    case object     // Object file
    case core       // Core dump
    // ... more
}
```

### Segment

```swift
let segment = binary.segments[0]

segment.name              // String - "__TEXT", "__DATA"
segment.vmAddress         // UInt64
segment.vmSize            // UInt64
segment.fileOffset        // UInt64
segment.fileSize          // UInt64
segment.initialProtection // VMProtection
segment.sections          // [Section]

// Check if address is in segment
segment.contains(address: 0x100003f40)

// Get specific section
let text = segment.section(named: "__text")
```

### Section

```swift
let section = segment.sections[0]

section.name      // String - "__text", "__cstring"
section.segment   // String - Parent segment name
section.address   // UInt64 - VM address
section.size      // UInt64
section.offset    // UInt32 - File offset
section.align     // UInt32 - Alignment
section.type      // SectionType
```

### Symbol

```swift
let symbol = binary.symbol(named: "_main")!

symbol.name       // String
symbol.address    // UInt64
symbol.type       // SymbolType
symbol.isDefined  // Bool - Defined in this binary
symbol.isExternal // Bool - Externally visible
symbol.isDebugSymbol // Bool
```

### LoadCommand

```swift
for cmd in binary.loadCommands {
    switch cmd.type {
    case .segment64:
        if case .segment(let seg) = cmd.payload { ... }
    case .symtab:
        if case .symtab(let sym) = cmd.payload { ... }
    case .loadDylib:
        if case .dylib(let dylib) = cmd.payload { ... }
    // ... more types
    default:
        break
    }
}
```

### CodeSignature

```swift
if let signature = try binary.parseCodeSignature() {
    // Code directory
    if let cd = signature.codeDirectory {
        cd.identifier     // String - Bundle ID
        cd.teamID         // String? - Team ID
        cd.flags          // CodeDirectoryFlags
        cd.hashType       // HashType
        cd.cdHashString   // String? - CDHash
        cd.isAdhoc        // Bool
        cd.isLinkerSigned // Bool
    }

    // Entitlements
    if let entitlements = signature.entitlements {
        entitlements.count   // Int
        entitlements.keys    // [String]
        entitlements["com.apple.security.app-sandbox"] // Any?
    }

    // SuperBlob info
    signature.superBlob.blobCount // Int
}
```

### StringExtractor

```swift
let extractor = StringExtractor(binary: binary)

// Extract all strings
let strings = try extractor.extractAllStrings()

// Extract from specific section types
let cstrings = try extractor.extractCStrings()

// Access extracted strings
for str in strings {
    str.value   // String - The string content
    str.offset  // UInt32 - File offset
    str.address // UInt64 - VM address
    str.section // String - Source section
}
```

### Error Handling

```swift
do {
    let binary = try MachOBinary(path: path)
} catch let error as MachOParseError {
    switch error {
    case .fileNotFound(let path):
        print("File not found: \(path)")
    case .invalidMagic(let found, let at):
        print("Invalid magic: \(found) at \(at)")
    case .architectureNotFound(let arch):
        print("Architecture not found: \(arch)")
    default:
        print("Parse error: \(error)")
    }
}
```

---

## Disassembler Module

Import:
```swift
import Disassembler
import MachOKit
```

### ARM64Disassembler

```swift
// Create disassembler
let binary = try MachOBinary(path: "/bin/ls")
let options = DisassemblyOptions(
    resolveSymbols: true,
    demangleSwift: true,
    annotatePAC: true,
    showBytes: false,
    showAddresses: true
)
let disassembler = ARM64Disassembler(binary: binary, options: options)
```

#### Disassemble Section

```swift
if let section = binary.section(segment: "__TEXT", section: "__text") {
    let result = try disassembler.disassembleSection(section, from: binary)

    print("Instructions: \(result.count)")
    print("Bytes: \(result.byteCount)")

    for instruction in result.instructions {
        print("\(instruction.address): \(instruction.mnemonic)")
    }
}
```

#### Disassemble Function

```swift
let result = try disassembler.disassembleFunction("_main", from: binary)

print("Function: \(result.functionName ?? "unknown")")
print("Start: 0x\(String(result.startAddress, radix: 16))")
print("End: 0x\(String(result.endAddress, radix: 16))")
```

#### Disassemble Range

```swift
let result = try disassembler.disassembleRange(
    from: 0x100003f40,
    to: 0x100003f80,
    in: binary
)
```

#### List Functions

```swift
let functions = disassembler.listFunctions(in: binary)

for (name, address) in functions {
    print("0x\(String(address, radix: 16)): \(name)")
}
```

#### Format Instructions

```swift
for instruction in result.instructions {
    let formatted = disassembler.format(instruction)
    print(formatted)
}
```

### Instruction

```swift
let instruction = result.instructions[0]

instruction.address   // UInt64
instruction.encoding  // UInt32 - Raw bytes
instruction.mnemonic  // String - "mov", "add", etc.
instruction.operands  // [Operand]
instruction.category  // InstructionCategory
instruction.annotation // String? - Symbol or PAC info
```

### InstructionCategory

```swift
enum InstructionCategory {
    case dataProcessing  // Arithmetic, logical
    case branch          // Branches, calls
    case loadStore       // Memory access
    case system          // System instructions
    case unknown
}
```

### DisassemblyOptions

```swift
struct DisassemblyOptions {
    var resolveSymbols: Bool   // Resolve addresses to symbols
    var demangleSwift: Bool    // Demangle Swift names
    var annotatePAC: Bool      // Annotate PAC instructions
    var showBytes: Bool        // Show raw instruction bytes
    var showAddresses: Bool    // Show instruction addresses
}
```

---

## DebuggerCore Module

Import:
```swift
import DebuggerCore
```

### PermissionChecker

Check system permissions without debugging.

```swift
let checker = PermissionChecker()

// Check capabilities
checker.canParse       // Bool - Always true
checker.canDisassemble // Bool - Always true
checker.canDebug       // Bool - Requires entitlements

// Get status
let status = checker.status
status.staticAnalysis      // Bool
status.disassembly         // Bool
status.debugging           // Bool
status.sipEnabled          // Bool
status.developerToolsEnabled // Bool
status.debuggerEntitlement // Bool

// Get tier
let tier = checker.tier    // .full, .analysis, .readOnly

// Get guidance
let guidance = checker.guidance // String with instructions
```

### Debugger

Attach to and control processes.

```swift
let debugger = Debugger()

// Attach to process
try debugger.attach(to: pid)

// Check state
debugger.isAttached  // Bool
debugger.pid         // Int32?
debugger.processName // String?

// Control execution
try debugger.continueExecution()
try debugger.singleStep()

// Breakpoints
let bp = try debugger.setBreakpoint(at: 0x100003f40)
try debugger.removeBreakpoint(bp)
let breakpoints = debugger.breakpoints

// Registers
let regs = try debugger.readRegisters()
try debugger.writeRegisters(regs)

// Memory
let data = try debugger.readMemory(at: 0x100000000, count: 16)
try debugger.writeMemory(at: 0x100000000, data: data)

// Detach
try debugger.detach()
```

### ARM64Registers

```swift
var regs = try debugger.readRegisters()

// General purpose registers
regs.x[0]   // x0
regs.x[28]  // x28
regs.fp     // x29 (frame pointer)
regs.lr     // x30 (link register)

// Special registers
regs.sp     // Stack pointer
regs.pc     // Program counter
regs.cpsr   // Current program status register

// CPSR flags
regs.negativeFlag  // N flag
regs.zeroFlag      // Z flag
regs.carryFlag     // C flag
regs.overflowFlag  // V flag

// Modify and write back
regs.pc = 0x100003f40
try debugger.writeRegisters(regs)
```

### Breakpoint

```swift
let bp = try debugger.setBreakpoint(at: 0x100003f40)

bp.id       // Int - Unique ID
bp.address  // UInt64
bp.isActive // Bool

// Remove
try debugger.removeBreakpoint(bp)
// Or by ID
try debugger.removeBreakpoint(id: bp.id)
```

### Error Handling

```swift
do {
    try debugger.attach(to: pid)
} catch let error as DebuggerError {
    switch error {
    case .processNotFound(let pid):
        print("Process \(pid) not found")
    case .permissionDenied(let op, let guidance):
        print("Permission denied: \(op)")
        print(guidance)
    case .sipBlocking(let path, _):
        print("SIP blocks: \(path)")
    case .attachFailed(let pid, let reason):
        print("Attach failed: \(reason)")
    default:
        print("Error: \(error)")
    }
}
```

---

## Complete Example

```swift
import MachOKit
import Disassembler
import DebuggerCore

func analyzeBinary(at path: String) throws {
    // 1. Parse the binary
    let binary = try MachOBinary(path: path)

    print("Binary: \(binary.path)")
    print("CPU: \(binary.header.cpuType)")
    print("Type: \(binary.header.fileType)")
    print("Segments: \(binary.segments.count)")

    // 2. List symbols
    if let symbols = binary.symbols {
        let defined = symbols.filter { $0.isDefined }
        print("Defined symbols: \(defined.count)")

        for symbol in defined.prefix(10) {
            print("  0x\(String(symbol.address, radix: 16)): \(symbol.name)")
        }
    }

    // 3. Check code signature
    if let signature = try binary.parseCodeSignature() {
        print("Signed: Yes")
        if let cd = signature.codeDirectory {
            print("  ID: \(cd.identifier)")
            print("  Ad-hoc: \(cd.isAdhoc)")
        }
    }

    // 4. Disassemble _main
    let disasm = ARM64Disassembler(binary: binary)
    if let result = try? disasm.disassembleFunction("_main", from: binary) {
        print("_main: \(result.count) instructions")
        for instr in result.instructions.prefix(5) {
            print("  \(disasm.format(instr))")
        }
    }

    // 5. Extract strings
    let extractor = StringExtractor(binary: binary)
    let strings = try extractor.extractCStrings()
    print("Strings: \(strings.count)")
}

// Run analysis
try analyzeBinary(at: "/bin/ls")
```

---

## Thread Safety

All MachScope types are `Sendable` and safe to use from multiple threads:

```swift
import MachOKit

// Safe to share across tasks
let binary = try MachOBinary(path: "/bin/ls")

await withTaskGroup(of: Void.self) { group in
    group.addTask {
        print("Segments: \(binary.segments.count)")
    }
    group.addTask {
        print("Symbols: \(binary.symbols?.count ?? 0)")
    }
}
```
