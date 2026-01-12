# Architecture Guide

Technical overview of MachScope's design and implementation.

## Overview

MachScope is built as a modular Swift application with four main components:

```
┌─────────────────────────────────────────────────────────┐
│                    MachScope CLI                         │
│         (Commands, Formatters, Argument Parsing)         │
└─────────────────────────────────────────────────────────┘
                            │
            ┌───────────────┼───────────────┐
            ▼               ▼               ▼
┌───────────────┐  ┌───────────────┐  ┌───────────────┐
│   MachOKit    │  │  Disassembler │  │ DebuggerCore  │
│               │  │               │  │               │
│ Mach-O Parser │  │ ARM64 Decoder │  │ Process Debug │
└───────────────┘  └───────────────┘  └───────────────┘
        │                  │                  │
        └──────────────────┴──────────────────┘
                           │
                    ┌──────┴──────┐
                    │   Darwin    │
                    │  (System)   │
                    └─────────────┘
```

## Module Dependencies

```
MachScope (CLI)
    ├── MachOKit
    ├── Disassembler ──► MachOKit (SymbolResolving protocol)
    └── DebuggerCore ──► MachOKit, Disassembler
```

- **MachOKit**: No dependencies (standalone)
- **Disassembler**: Depends on MachOKit for symbol resolution
- **DebuggerCore**: Depends on both for binary analysis during debugging
- **MachScope**: CLI that ties everything together

## Directory Structure

```
MachScope/
├── Package.swift                    # Swift Package manifest
├── Sources/
│   ├── MachOKit/                    # Core Mach-O parsing
│   │   ├── MachOBinary.swift        # Main entry point
│   │   ├── Header/                  # Header parsing
│   │   ├── LoadCommands/            # Load command parsing
│   │   ├── Sections/                # Segments and sections
│   │   ├── Symbols/                 # Symbol table
│   │   ├── CodeSignature/           # Code signing
│   │   ├── IO/                      # Binary reading
│   │   └── Errors/                  # Error types
│   │
│   ├── Disassembler/                # ARM64 disassembly
│   │   ├── ARM64Disassembler.swift  # Main entry point
│   │   ├── Instruction.swift        # Instruction model
│   │   ├── Decoder/                 # Instruction decoders
│   │   ├── Formatter/               # Output formatting
│   │   ├── Analysis/                # Symbol resolution, PAC
│   │   └── Errors/                  # Error types
│   │
│   ├── DebuggerCore/                # Process debugging
│   │   ├── Debugger.swift           # Main entry point
│   │   ├── Process/                 # Process management
│   │   ├── Breakpoints/             # Breakpoint handling
│   │   ├── Memory/                  # Memory access
│   │   ├── Exceptions/              # Mach exceptions
│   │   ├── Permissions/             # Permission checking
│   │   └── Errors/                  # Error types
│   │
│   └── MachScope/                   # CLI application
│       ├── main.swift               # Entry point
│       ├── Commands/                # Command implementations
│       ├── Output/                  # Formatters
│       └── Utilities/               # Argument parsing
│
├── Tests/                           # Test suites
├── Resources/                       # Entitlements
└── docs/                            # Documentation
```

## MachOKit Module

### Purpose
Parse and analyze Mach-O binary files.

### Key Types

#### MachOBinary
Main entry point for parsing.

```swift
public struct MachOBinary: Sendable {
    public let path: String
    public let fileSize: UInt64
    public let header: MachHeader
    public let loadCommands: [LoadCommand]
    public let segments: [Segment]

    public var symbols: [Symbol]?
    public var dylibDependencies: [DylibCommand]

    public func parseCodeSignature() throws -> CodeSignature?
}
```

#### BinaryReader
Safe, bounds-checked binary reading.

```swift
public struct BinaryReader: Sendable {
    public func readUInt32(at offset: Int) throws -> UInt32
    public func readUInt64(at offset: Int) throws -> UInt64
    public func readBytes(at offset: Int, count: Int) throws -> Data
    public func slice(at offset: Int, count: Int) throws -> BinaryReader
}
```

### Memory Management

- Files < 10MB: Loaded into memory
- Files >= 10MB: Memory-mapped with `mmap()`
- Lazy symbol table loading
- Memory usage target: < 2x file size

### Error Handling

All errors are typed via `MachOParseError`:

```swift
public enum MachOParseError: Error {
    case fileNotFound(path: String)
    case invalidMagic(found: UInt32, at: Int)
    case truncatedHeader(offset: Int, needed: Int, available: Int)
    case architectureNotFound(String)
    // ... more cases
}
```

## Disassembler Module

### Purpose
Decode and format ARM64 instructions.

### Key Types

#### ARM64Disassembler
Main disassembly interface.

```swift
public struct ARM64Disassembler: Sendable {
    public init(binary: MachOBinary, options: DisassemblyOptions)

    public func disassembleSection(_ section: Section, from binary: MachOBinary) throws -> DisassemblyResult
    public func disassembleFunction(_ name: String, from binary: MachOBinary) throws -> DisassemblyResult
    public func listFunctions(in binary: MachOBinary) -> [(name: String, address: UInt64)]
}
```

#### Instruction
Decoded instruction representation.

```swift
public struct Instruction: Sendable {
    public let address: UInt64
    public let encoding: UInt32
    public let mnemonic: String
    public let operands: [Operand]
    public let category: InstructionCategory
    public var annotation: String?
}
```

### Instruction Categories

- **Data Processing**: ADD, SUB, MOV, AND, ORR, etc.
- **Branch**: B, BL, BR, BLR, RET, CBZ, TBZ
- **Load/Store**: LDR, STR, LDP, STP, LDXR, STXR
- **System**: SVC, NOP, MSR, MRS, PAC instructions

### Decoder Architecture

```
InstructionDecoder (base)
    ├── DataProcessing.swift  (arithmetic, logical)
    ├── Branch.swift          (branches, calls)
    ├── LoadStore.swift       (memory access)
    └── System.swift          (system, PAC)
```

Each decoder handles specific instruction patterns based on ARM64 encoding.

## DebuggerCore Module

### Purpose
Attach to and control running processes.

### Key Types

#### Debugger
Main debugging interface.

```swift
public final class Debugger: @unchecked Sendable {
    public func attach(to pid: Int32) throws
    public func detach() throws
    public func continueExecution() throws
    public func singleStep() throws
    public func readRegisters() throws -> ARM64Registers
    public func setBreakpoint(at address: UInt64) throws -> Breakpoint
}
```

#### ARM64Registers
CPU register state.

```swift
public struct ARM64Registers: Sendable {
    public var x: [UInt64]  // x0-x28
    public var fp: UInt64   // x29
    public var lr: UInt64   // x30
    public var sp: UInt64
    public var pc: UInt64
    public var cpsr: UInt32
}
```

### System Interactions

| Operation | System API |
|-----------|------------|
| Attach | `ptrace(PT_ATTACHEXC, ...)` |
| Detach | `ptrace(PT_DETACH, ...)` |
| Task Port | `task_for_pid(...)` |
| Read Memory | `vm_read(...)` |
| Write Memory | `vm_write(...)` + `vm_protect(...)` |
| Threads | `task_threads(...)` |
| Registers | `thread_get_state(...)` |
| Exceptions | Mach exception ports |

### Exception Handling

MachScope uses Mach exception ports for debugging events:

```
Process ──► Exception ──► MachExceptionServer ──► ExceptionHandler ──► Debugger
```

## CLI Module

### Command Structure

Each command is a struct with a static `execute` method:

```swift
public struct ParseCommand: Sendable {
    public static func execute(args: ParsedArguments) -> Int32
}
```

### Output Formatters

- **TextFormatter**: Human-readable output with optional ANSI colors
- **JSONFormatter**: Machine-readable JSON output

### Argument Parsing

Custom `ArgumentParser` handles:
- Commands: `parse`, `disasm`, `check-permissions`, `debug`
- Flags: `--json`, `--verbose`, `--all`
- Options: `--arch arm64`, `--function _main`
- Positional: File paths, PIDs

## Design Principles

### 1. Pure Swift
- No Objective-C bridges
- C interop wrapped in type-safe abstractions
- Swift 6 strict concurrency (`Sendable` everywhere)

### 2. Memory Safety
- Bounds checking on all binary reads
- No force unwrapping (`!`) in production
- Exhaustive error types

### 3. Performance
- Memory-mapped I/O for large files
- Lazy loading (symbols loaded on demand)
- Efficient data structures

### 4. Modularity
- Protocol-based boundaries
- No circular dependencies
- Each module independently testable

### 5. Security
- Graceful degradation without permissions
- Clear permission guidance
- No silent failures

## Protocol Boundaries

### SymbolResolving
Used by Disassembler to resolve addresses to names.

```swift
public protocol SymbolResolving: Sendable {
    func resolve(address: UInt64) -> String?
}
```

### BinaryProviding
Abstraction for binary data access.

```swift
public protocol BinaryProviding: Sendable {
    func readBytes(at offset: Int, count: Int) throws -> Data
}
```

## Testing Strategy

### Test Organization

```
Tests/
├── MachOKitTests/       # Parser tests
├── DisassemblerTests/   # Decoder tests
├── DebuggerCoreTests/   # Debug tests
└── IntegrationTests/    # End-to-end tests
```

### Test Fixtures

Located in `Tests/MachOKitTests/Fixtures/`:
- `simple_arm64`: Basic ARM64 executable
- `fat_binary`: Universal binary (arm64 + x86_64)
- `malformed/`: Invalid binaries for error testing

### Test Coverage

- Unit tests for each component
- Integration tests for workflows
- Error case testing
- 319+ tests, 0 failures

## Future Architecture Considerations

### Extensibility Points

1. **New CPU architectures**: Add new decoder modules
2. **New load commands**: Extend `LoadCommand` enum
3. **New output formats**: Add formatters (XML, YAML)
4. **Plugin system**: Protocol-based extensions

### Performance Improvements

1. Parallel section parsing
2. Instruction caching
3. Incremental parsing
4. Background indexing
