# Data Model: MachScope Binary Analysis Tool

**Feature Branch**: `001-macos-binary-analysis`
**Created**: 2026-01-12
**Source**: [spec.md](./spec.md)

## Overview

MachScope operates on binary files and process state. There is no persistent storage - all data is derived from input files or live process inspection. This document defines the domain entities, their attributes, relationships, and validation rules.

---

## Core Entities

### 1. MachOBinary

The root entity representing a parsed Mach-O file.

| Attribute | Type | Description | Validation |
|-----------|------|-------------|------------|
| `path` | `String` | Absolute path to source file | Non-empty, file exists |
| `header` | `MachHeader` | Parsed Mach-O header | Valid magic number |
| `loadCommands` | `[LoadCommand]` | Ordered load commands | Count matches header.ncmds |
| `segments` | `[Segment]` | Memory segments | Derived from LC_SEGMENT_64 |
| `symbols` | `[Symbol]?` | Symbol table (lazy) | Derived from LC_SYMTAB |
| `codeSignature` | `CodeSignature?` | Code signature data | Optional, from LC_CODE_SIGNATURE |
| `fileSize` | `UInt64` | Total file size in bytes | > 0 |
| `isMemoryMapped` | `Bool` | Whether using mmap | True if fileSize > 10MB |

**State Transitions**: None (immutable after parsing)

**Relationships**:
- Contains 1..* `LoadCommand`
- Contains 0..* `Segment`
- Contains 0..* `Symbol`
- Contains 0..1 `CodeSignature`

---

### 2. FatBinary

Universal binary containing multiple architecture slices.

| Attribute | Type | Description | Validation |
|-----------|------|-------------|------------|
| `path` | `String` | Absolute path to source file | Non-empty, file exists |
| `architectures` | `[FatArch]` | Architecture descriptors | Count > 0 |
| `fileSize` | `UInt64` | Total file size | > 0 |

**Nested: FatArch**

| Attribute | Type | Description |
|-----------|------|-------------|
| `cpuType` | `CPUType` | CPU architecture |
| `cpuSubtype` | `CPUSubtype` | CPU subtype |
| `offset` | `UInt32` | Offset to Mach-O slice |
| `size` | `UInt32` | Size of slice |
| `alignment` | `UInt32` | Alignment (power of 2) |

**Relationships**:
- Contains 1..* `FatArch`
- Each `FatArch` references a `MachOBinary` slice

---

### 3. MachHeader

The 64-bit Mach-O header structure.

| Attribute | Type | Description | Validation |
|-----------|------|-------------|------------|
| `magic` | `UInt32` | Magic number | 0xFEEDFACF (64-bit) |
| `cpuType` | `CPUType` | CPU type | CPU_TYPE_ARM64 supported |
| `cpuSubtype` | `CPUSubtype` | CPU subtype | Valid ARM64 subtype |
| `fileType` | `FileType` | Binary type | MH_EXECUTE, MH_DYLIB, etc. |
| `numberOfCommands` | `UInt32` | Load command count | > 0 |
| `sizeOfCommands` | `UInt32` | Total size of load commands | > 0 |
| `flags` | `MachHeaderFlags` | Binary flags | Bitmask |

**Enums**:

```
CPUType:
  - arm64 (0x0100000C)

CPUSubtype:
  - all (0)
  - arm64e (2)

FileType:
  - execute (MH_EXECUTE = 2)
  - dylib (MH_DYLIB = 6)
  - bundle (MH_BUNDLE = 8)
  - object (MH_OBJECT = 1)
  - core (MH_CORE = 4)
  - dsym (MH_DSYM = 10)

MachHeaderFlags (bitmask):
  - noUndefinedRefs (0x1)
  - incrementalLink (0x2)
  - dynamicLink (0x4)
  - twolevel (0x80)
  - pie (0x200000)
```

---

### 4. LoadCommand

Base structure for all load commands.

| Attribute | Type | Description | Validation |
|-----------|------|-------------|------------|
| `type` | `LoadCommandType` | Command type | Known or unknown |
| `size` | `UInt32` | Total command size | >= 8 bytes |
| `offset` | `Int` | File offset | Within bounds |
| `payload` | `LoadCommandPayload` | Type-specific data | Varies by type |

**LoadCommandType Enum**:

```
segment64 (0x19)
symtab (0x02)
dysymtab (0x0B)
loadDylib (0x0C)
codeSignature (0x1D)
functionStarts (0x26)
main (0x80000028)
buildVersion (0x32)
uuid (0x1B)
sourceVersion (0x2A)
encryptionInfo64 (0x2C)
linkerOption (0x2D)
unknown(UInt32)
```

**LoadCommandPayload (tagged union)**:

```
segment(SegmentCommand)
symtab(SymtabCommand)
dysymtab(DysymtabCommand)
dylib(DylibCommand)
codeSignature(LinkeditDataCommand)
functionStarts(LinkeditDataCommand)
main(EntryPointCommand)
buildVersion(BuildVersionCommand)
uuid(UUIDCommand)
raw(Data)
```

---

### 5. Segment

Memory segment from LC_SEGMENT_64.

| Attribute | Type | Description | Validation |
|-----------|------|-------------|------------|
| `name` | `String` | Segment name | 1-16 chars |
| `vmAddress` | `UInt64` | Virtual memory address | - |
| `vmSize` | `UInt64` | Virtual memory size | - |
| `fileOffset` | `UInt64` | File offset | Within file bounds |
| `fileSize` | `UInt64` | Size in file | <= vmSize |
| `maxProtection` | `VMProtection` | Max VM protection | - |
| `initialProtection` | `VMProtection` | Initial protection | - |
| `sections` | `[Section]` | Contained sections | Count matches header |
| `flags` | `UInt32` | Segment flags | - |

**VMProtection (bitmask)**:

```
read (0x1)
write (0x2)
execute (0x4)
```

**Relationships**:
- Parent: `MachOBinary`
- Contains 0..* `Section`

---

### 6. Section

Section within a segment.

| Attribute | Type | Description | Validation |
|-----------|------|-------------|------------|
| `name` | `String` | Section name | 1-16 chars |
| `segmentName` | `String` | Parent segment name | Matches parent |
| `address` | `UInt64` | Virtual address | - |
| `size` | `UInt64` | Size in bytes | - |
| `offset` | `UInt32` | File offset | - |
| `alignment` | `UInt32` | Alignment (power of 2) | 0-15 |
| `relocOffset` | `UInt32` | Relocation offset | - |
| `numberOfRelocs` | `UInt32` | Relocation count | - |
| `type` | `SectionType` | Section type | - |
| `attributes` | `SectionAttributes` | Section attributes | - |

**SectionType Enum**:

```
regular (0x00)
zeroFill (0x01)
cstringLiterals (0x02)
symbolStubs (0x08)
lazySymbolPointers (0x07)
nonLazySymbolPointers (0x06)
```

**Common Sections**:

| Section | Segment | Purpose |
|---------|---------|---------|
| `__text` | `__TEXT` | Executable code |
| `__stubs` | `__TEXT` | Symbol stubs |
| `__cstring` | `__TEXT` | C strings |
| `__data` | `__DATA` | Initialized data |
| `__bss` | `__DATA` | Uninitialized data |
| `__got` | `__DATA_CONST` | Global offset table |

---

### 7. Symbol

Symbol table entry.

| Attribute | Type | Description | Validation |
|-----------|------|-------------|------------|
| `name` | `String` | Symbol name | Non-empty |
| `address` | `UInt64` | Symbol address | - |
| `type` | `SymbolType` | Symbol type | - |
| `section` | `UInt8` | Section index | 0 = undefined |
| `description` | `UInt16` | Descriptor flags | - |
| `isExternal` | `Bool` | External linkage | - |
| `isPrivateExternal` | `Bool` | Private external | - |
| `isDefined` | `Bool` | Defined in binary | - |

**SymbolType Enum**:

```
undefined (N_UNDF)
absolute (N_ABS)
section (N_SECT)
prebound (N_PBUD)
indirect (N_INDR)
```

**Relationships**:
- Parent: `MachOBinary`
- References: `Section` (by index)

---

### 8. CodeSignature

Code signature information.

| Attribute | Type | Description | Validation |
|-----------|------|-------------|------------|
| `offset` | `UInt32` | File offset to signature | Within bounds |
| `size` | `UInt32` | Signature size | > 0 |
| `codeDirectory` | `CodeDirectory?` | Main signature data | - |
| `entitlements` | `String?` | XML entitlements | Valid XML plist |
| `derEntitlements` | `Data?` | DER-encoded entitlements | - |
| `cmsSignature` | `Data?` | CMS signature blob | - |

**Nested: CodeDirectory**

| Attribute | Type | Description |
|-----------|------|-------------|
| `identifier` | `String` | Bundle identifier |
| `teamID` | `String?` | Team ID |
| `cdHash` | `Data` | CodeDirectory hash |
| `hashType` | `HashType` | Hash algorithm |
| `pageSize` | `UInt32` | Hash page size |
| `codeLimit` | `UInt32` | Code limit for hashing |
| `version` | `UInt32` | CodeDirectory version |

**HashType Enum**:

```
sha1 (1)
sha256 (2)
sha256Truncated (3)
sha384 (4)
```

---

### 9. Instruction

Decoded ARM64 instruction.

| Attribute | Type | Description | Validation |
|-----------|------|-------------|------------|
| `address` | `UInt64` | Virtual address | - |
| `encoding` | `UInt32` | Raw instruction bytes | - |
| `mnemonic` | `String` | Instruction mnemonic | Non-empty |
| `operands` | `[Operand]` | Instruction operands | 0-5 operands |
| `category` | `InstructionCategory` | Instruction category | - |
| `annotation` | `String?` | Optional annotation | e.g., PAC info |
| `targetAddress` | `UInt64?` | Branch/call target | For control flow |
| `targetSymbol` | `String?` | Resolved symbol name | If available |

**Operand (tagged union)**:

```
register(RegisterOperand)
immediate(Int64)
address(UInt64)
memoryBase(MemoryOperand)
shiftedRegister(ShiftedRegisterOperand)
condition(ConditionCode)
```

**InstructionCategory Enum**:

```
dataProcessing
branch
loadStore
system
simd
pac        // Pointer authentication
unknown
```

**Relationships**:
- Parent: Disassembly context
- References: `Symbol` (for target resolution)

---

### 10. DebugSession

Active debugging session state.

| Attribute | Type | Description | Validation |
|-----------|------|-------------|------------|
| `pid` | `pid_t` | Process ID | > 0 |
| `taskPort` | `mach_port_t` | Mach task port | Valid port |
| `isAttached` | `Bool` | Attachment status | - |
| `threads` | `[ThreadState]` | Process threads | Count >= 1 |
| `breakpoints` | `[Breakpoint]` | Active breakpoints | - |
| `exceptionPort` | `mach_port_t` | Exception handler port | Valid if attached |

**State Transitions**:

```
[Detached] --attach()--> [Attached]
[Attached] --continue()--> [Running]
[Running] --breakpoint/step--> [Stopped]
[Stopped] --continue()--> [Running]
[Attached/Stopped] --detach()--> [Detached]
```

**Nested: ThreadState**

| Attribute | Type | Description |
|-----------|------|-------------|
| `threadID` | `thread_t` | Thread port |
| `registers` | `ARM64Registers` | Register state |
| `isSuspended` | `Bool` | Suspension state |

**Relationships**:
- Contains 0..* `Breakpoint`
- Contains 1..* `ThreadState`

---

### 11. Breakpoint

Software breakpoint state.

| Attribute | Type | Description | Validation |
|-----------|------|-------------|------------|
| `id` | `Int` | Unique identifier | > 0, unique |
| `address` | `UInt64` | Breakpoint address | - |
| `originalBytes` | `UInt32` | Original instruction | - |
| `isEnabled` | `Bool` | Enabled state | - |
| `hitCount` | `Int` | Number of hits | >= 0 |
| `symbol` | `String?` | Associated symbol | If set by name |

**State Transitions**:

```
[Created] --enable()--> [Enabled]
[Enabled] --disable()--> [Disabled]
[Enabled] --hit()--> [Enabled] (hitCount++)
[Enabled/Disabled] --remove()--> [Removed]
```

---

### 12. ARM64Registers

ARM64 register state for debugging.

| Attribute | Type | Description |
|-----------|------|-------------|
| `x0` - `x28` | `UInt64` | General purpose registers |
| `x29` | `UInt64` | Frame pointer (FP) |
| `x30` | `UInt64` | Link register (LR) |
| `sp` | `UInt64` | Stack pointer |
| `pc` | `UInt64` | Program counter |
| `cpsr` | `UInt32` | Current program status |

**CPSR Flags** (partial):

```
N (31): Negative
Z (30): Zero
C (29): Carry
V (28): Overflow
```

---

## Entity Relationship Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        MachOBinary                               │
│ ┌─────────────┐  ┌──────────────────┐  ┌───────────────┐        │
│ │ MachHeader  │  │ [LoadCommand]    │  │ [Segment]     │        │
│ │             │  │                  │  │   └─[Section] │        │
│ └─────────────┘  └──────────────────┘  └───────────────┘        │
│                                                                  │
│ ┌─────────────┐  ┌──────────────────┐                           │
│ │ [Symbol]    │  │ CodeSignature?   │                           │
│ │             │  │ └─CodeDirectory  │                           │
│ └─────────────┘  └──────────────────┘                           │
└─────────────────────────────────────────────────────────────────┘
          ▲
          │ references
          │
┌─────────────────────────────────────────────────────────────────┐
│                         FatBinary                                │
│ ┌─────────────────────────────────────────┐                     │
│ │ [FatArch] ──────────────────────────────┼───▶ MachOBinary     │
│ │   cpuType, offset, size                 │         (slice)     │
│ └─────────────────────────────────────────┘                     │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                      Disassembly Output                          │
│ ┌─────────────┐                                                  │
│ │ [Instruction]│───references───▶ Symbol (target)               │
│ │   └─[Operand]│                                                 │
│ └─────────────┘                                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                       DebugSession                               │
│ ┌─────────────┐  ┌──────────────────┐                           │
│ │ [ThreadState]│  │ [Breakpoint]     │                          │
│ │  └─Registers │  │                  │                          │
│ └─────────────┘  └──────────────────┘                           │
└─────────────────────────────────────────────────────────────────┘
```

---

## Validation Rules Summary

| Entity | Rule | Error Type |
|--------|------|------------|
| MachOBinary | Magic must be 0xFEEDFACF | `invalidMagic` |
| MachOBinary | CPU type must be ARM64 | `unsupportedCPUType` |
| LoadCommand | Size must be >= 8 bytes | `truncatedLoadCommand` |
| LoadCommand | Total size must match header | `loadCommandSizeMismatch` |
| Segment | File offset must be within file | `segmentOutOfBounds` |
| Section | Offset + size must be within segment | `sectionOutOfBounds` |
| FatBinary | Magic must be 0xCAFEBABE | `invalidFatMagic` |
| FatBinary | At least one architecture | `emptyFatBinary` |
| Symbol | Name must be non-empty | `emptySymbolName` |
| Instruction | Encoding must be 4 bytes | `truncatedInstruction` |
| Breakpoint | Address must be in executable segment | `invalidBreakpointAddress` |
| DebugSession | PID must be > 0 | `invalidPID` |

---

## JSON Serialization

All entities support JSON serialization via `Codable`. Example output format:

```json
{
  "path": "/path/to/binary",
  "header": {
    "magic": "0xfeedfacf",
    "cpuType": "arm64",
    "cpuSubtype": "all",
    "fileType": "execute",
    "numberOfCommands": 25,
    "sizeOfCommands": 2776,
    "flags": ["pie", "twolevel", "dynamicLink"]
  },
  "segments": [
    {
      "name": "__TEXT",
      "vmAddress": "0x100000000",
      "vmSize": 16384,
      "sections": [
        {
          "name": "__text",
          "address": "0x100003f40",
          "size": 1234
        }
      ]
    }
  ],
  "symbols": [
    {
      "name": "_main",
      "address": "0x100003f40",
      "type": "section",
      "isExternal": true
    }
  ]
}
```

---

**Document Version**: 1.0
**Last Updated**: 2026-01-12
