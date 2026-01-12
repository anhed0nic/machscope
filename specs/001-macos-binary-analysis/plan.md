# Implementation Plan: MachScope Binary Analysis Tool

**Branch**: `001-macos-binary-analysis` | **Date**: 2026-01-12 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-macos-binary-analysis/spec.md`

## Summary

MachScope is a native macOS binary analysis tool providing Mach-O parsing, ARM64 disassembly, and optional process debugging. The implementation uses pure Swift 6.2.3 with strict concurrency, organized as a multi-target Swift Package with no external dependencies. Core technical approach: memory-mapped file access for performance, custom ARM64 instruction decoder, and Mach API-based debugging with graceful permission degradation.

## Technical Context

**Language/Version**: Swift 6.2.3 with `SWIFT_STRICT_CONCURRENCY=complete`
**Primary Dependencies**: None (Apple system frameworks only: Darwin, Foundation, Security)
**Storage**: N/A (file-based analysis, no persistent storage)
**Testing**: XCTest with committed binary fixtures
**Target Platform**: arm64-apple-macosx26.0
**Project Type**: Single Swift Package with multiple library targets + CLI executable
**Performance Goals**: Parse <50MB binaries in <5s; handle 500MB binaries; memory <2x file size
**Constraints**: Offline-only, no external dependencies, graceful permission degradation
**Scale/Scope**: Single-user CLI tool analyzing individual binaries

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Implementation Approach |
|-----------|--------|------------------------|
| I. Security & Permission Handling | PASS | Graceful degradation implemented; debugger optional; actionable error messages with System Settings paths |
| II. Pure Swift Implementation | PASS | Swift 6.2.3 with strict concurrency; C interop via type-safe wrappers only |
| III. Memory Safety & Robustness | PASS | Bounds-checked parsing; domain-specific errors; no force-unwrapping |
| IV. Performance Optimization | PASS | mmap() for >10MB files; lazy parsing; streaming disassembly |
| V. Modular Architecture | PASS | Four targets (MachOKit, Disassembler, DebuggerCore, CLI) with protocol boundaries |
| VI. Comprehensive Testing | PASS | XCTest with committed fixtures; unit + integration tests |

**Platform Constraints Check**:
- Target: arm64-apple-macosx26 ✓
- Swift: 6.2.3 ✓
- Dependencies: None (system frameworks only) ✓

## Project Structure

### Documentation (this feature)

```text
specs/001-macos-binary-analysis/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (CLI interface contracts)
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
Package.swift            # Swift Package manifest

Sources/
├── MachOKit/                    # Core Mach-O parsing library
│   ├── MachOBinary.swift        # Main entry point
│   ├── Header/
│   │   ├── MachHeader.swift     # mach_header_64 parsing
│   │   ├── FatHeader.swift      # Universal binary handling
│   │   └── CPUType.swift        # CPU type enums
│   ├── LoadCommands/
│   │   ├── LoadCommand.swift    # Base load command
│   │   ├── SegmentCommand.swift # LC_SEGMENT_64
│   │   ├── SymtabCommand.swift  # LC_SYMTAB
│   │   ├── DyldCommand.swift    # LC_LOAD_DYLIB, etc.
│   │   └── CodeSignatureCommand.swift
│   ├── Sections/
│   │   ├── Segment.swift
│   │   ├── Section.swift
│   │   └── SectionType.swift
│   ├── Symbols/
│   │   ├── Symbol.swift
│   │   ├── SymbolTable.swift
│   │   └── StringTable.swift
│   ├── CodeSignature/
│   │   ├── SuperBlob.swift
│   │   ├── CodeDirectory.swift
│   │   └── Entitlements.swift
│   ├── IO/
│   │   ├── BinaryReader.swift   # Bounds-checked reading
│   │   └── MemoryMappedFile.swift
│   └── Errors/
│       └── MachOParseError.swift
│
├── Disassembler/                # ARM64 instruction decoder
│   ├── ARM64Disassembler.swift  # Main entry point
│   ├── Instruction.swift        # Decoded instruction model
│   ├── Decoder/
│   │   ├── InstructionDecoder.swift
│   │   ├── DataProcessing.swift
│   │   ├── Branch.swift
│   │   ├── LoadStore.swift
│   │   └── System.swift
│   ├── Formatter/
│   │   ├── InstructionFormatter.swift
│   │   └── OperandFormatter.swift
│   ├── Analysis/
│   │   ├── SymbolResolver.swift
│   │   ├── PACAnnotator.swift
│   │   └── SwiftDemangler.swift
│   └── Errors/
│       └── DisassemblyError.swift
│
├── DebuggerCore/                # Process debugging (optional)
│   ├── Debugger.swift           # Main entry point
│   ├── Process/
│   │   ├── TaskPort.swift       # task_for_pid wrapper
│   │   ├── ProcessAttachment.swift
│   │   └── ThreadState.swift
│   ├── Breakpoints/
│   │   ├── Breakpoint.swift
│   │   └── BreakpointManager.swift
│   ├── Memory/
│   │   ├── MemoryReader.swift
│   │   └── MemoryWriter.swift
│   ├── Exceptions/
│   │   ├── ExceptionHandler.swift
│   │   └── MachExceptionServer.swift
│   ├── Permissions/
│   │   ├── PermissionChecker.swift
│   │   ├── EntitlementValidator.swift
│   │   └── SIPDetector.swift
│   └── Errors/
│       └── DebuggerError.swift
│
└── MachScope/                   # CLI executable
    ├── main.swift               # Entry point
    ├── Commands/
    │   ├── ParseCommand.swift
    │   ├── DisasmCommand.swift
    │   ├── DebugCommand.swift
    │   └── CheckPermissionsCommand.swift
    ├── Output/
    │   ├── TextFormatter.swift
    │   └── JSONFormatter.swift
    └── Utilities/
        └── ArgumentParser.swift

Tests/
├── MachOKitTests/
│   ├── HeaderTests.swift
│   ├── LoadCommandTests.swift
│   ├── SegmentTests.swift
│   ├── SymbolTests.swift
│   ├── CodeSignatureTests.swift
│   └── Fixtures/               # Committed test binaries
│       ├── simple_arm64
│       ├── fat_binary
│       ├── signed_binary
│       └── malformed/
│           ├── truncated
│           └── invalid_magic
│
├── DisassemblerTests/
│   ├── DecoderTests.swift
│   ├── FormatterTests.swift
│   └── Fixtures/
│       └── instruction_samples.json
│
├── DebuggerCoreTests/
│   ├── PermissionTests.swift
│   └── BreakpointTests.swift
│
└── IntegrationTests/
    ├── ParseIntegrationTests.swift
    ├── DisasmIntegrationTests.swift
    └── EndToEndTests.swift

Resources/
└── MachScope.entitlements      # Debugger entitlements file
```

**Structure Decision**: Swift Package with four targets providing clean module separation. MachOKit and Disassembler are reusable libraries. DebuggerCore requires entitlements and is optional. MachScope CLI is a thin orchestration layer.

## Complexity Tracking

No constitution violations requiring justification. The four-target structure directly maps to the constitution's modular architecture principle (Principle V).

## Technical Decisions

### 1. Memory-Mapped File Access

**Decision**: Use `mmap()` via custom `MemoryMappedFile` wrapper for binaries >10MB

**Rationale**:
- Constitution Principle IV requires mmap for large files
- `Data(contentsOf:options:.mappedIfSafe)` doesn't provide fine control
- Custom wrapper enables proper cleanup and error handling

**Implementation**:
```swift
final class MemoryMappedFile: @unchecked Sendable {
    let pointer: UnsafeRawPointer
    let size: Int
    // Uses mmap() with PROT_READ, MAP_PRIVATE
}
```

### 2. Bounds-Checked Binary Reading

**Decision**: All buffer access through `BinaryReader` with explicit bounds validation

**Rationale**:
- Constitution Principle III mandates bounds checking
- Prevents crashes on malformed binaries
- Enables partial parsing with detailed error reporting

**Implementation**:
```swift
struct BinaryReader: Sendable {
    func read<T>(_ type: T.Type, at offset: Int) throws -> T
    // Throws MachOParseError.insufficientData if out of bounds
}
```

### 3. Custom ARM64 Decoder

**Decision**: Build custom decoder instead of using Capstone

**Rationale**:
- Constitution requires no external dependencies
- Full control over error handling and output format
- Can optimize for common Swift compiler patterns

**Scope**: Focus on common instruction categories:
- Data processing (ADD, SUB, MOV, etc.)
- Branches (B, BL, BR, RET)
- Loads/Stores (LDR, STR, LDP, STP)
- System (SVC, NOP, PAC instructions)

### 4. Protocol-Oriented Module Boundaries

**Decision**: All inter-module communication via protocols

**Rationale**:
- Constitution Principle V requires protocol boundaries
- Enables testing with mocks
- Supports future GUI without core changes

**Key Protocols**:
```swift
// In MachOKit
protocol BinaryProviding: Sendable {
    func segment(named: String) -> Segment?
    func symbols() -> [Symbol]
}

// In Disassembler
protocol SymbolResolving: Sendable {
    func symbol(at address: UInt64) -> String?
}
```

### 5. Graceful Permission Degradation

**Decision**: Tiered capability model based on available permissions

**Rationale**:
- Constitution Principle I requires graceful degradation
- Users without debugger entitlement still get parsing/disassembly

**Tiers**:
1. **Full**: All features (debugger entitlement + Developer Tools)
2. **Analysis**: Parse + Disassemble (no special permissions)
3. **Read-only**: Parse only (minimal permissions)

### 6. Error Handling Strategy

**Decision**: Domain-specific error enums with context

**Rationale**:
- Constitution Principle III requires descriptive errors
- Constitution Development Workflow requires context in errors

**Implementation**:
```swift
enum MachOParseError: Error, Sendable {
    case invalidMagic(found: UInt32, at: Int)
    case truncatedHeader(offset: Int, needed: Int, available: Int)
    case unsupportedCPUType(CPUType)
    // ... with full context
}
```

## Dependencies

### System Frameworks (Apple-provided)

| Framework | Purpose | Module |
|-----------|---------|--------|
| Foundation | Data, URL, JSON encoding | All |
| Darwin | mmap, ptrace, mach_* | MachOKit, DebuggerCore |
| Security | SecCodeCopySigningInformation | DebuggerCore |

### No External Dependencies

Per constitution Platform Constraints, no external dependencies are used.
