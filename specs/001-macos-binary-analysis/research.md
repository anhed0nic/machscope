# MachScope Research Document

**Date**: 2026-01-12
**Target Platform**: arm64-apple-macosx26
**Swift Version**: 6.2.3+

---

## Table of Contents

1. [Mach-O File Format](#1-mach-o-file-format)
2. [ARM64 Disassembly](#2-arm64-disassembly)
3. [Debugger Implementation](#3-debugger-implementation)
4. [Swift 6.2 Features](#4-swift-62-features)
5. [macOS Tahoe 26 Security](#5-macos-tahoe-26-security)
6. [Metal GPU Acceleration Evaluation](#6-metal-gpu-acceleration-evaluation)
7. [Implementation Recommendations](#7-implementation-recommendations)

---

## 1. Mach-O File Format

### 1.1 Header Structure (mach_header_64)

The 64-bit Mach-O header is defined in `/usr/include/mach-o/loader.h`:

```c
struct mach_header_64 {
    uint32_t      magic;        // MH_MAGIC_64 = 0xfeedfacf
    cpu_type_t    cputype;      // CPU_TYPE_ARM64 = 0x0100000C
    cpu_subtype_t cpusubtype;   // CPU_SUBTYPE_ARM64E for PAC support
    uint32_t      filetype;     // MH_EXECUTE, MH_DYLIB, etc.
    uint32_t      ncmds;        // Number of load commands
    uint32_t      sizeofcmds;   // Total size of load commands
    uint32_t      flags;        // Binary flags
    uint32_t      reserved;     // Reserved (64-bit only)
};
```

**Swift Implementation Approach:**
```swift
struct MachHeader64: Sendable {
    let magic: UInt32
    let cpuType: CPUType
    let cpuSubtype: CPUSubtype
    let fileType: FileType
    let numberOfCommands: UInt32
    let sizeOfCommands: UInt32
    let flags: MachHeaderFlags

    static let size = 32 // bytes

    init(from data: Data, at offset: Int) throws {
        guard offset + Self.size <= data.count else {
            throw MachOParseError.truncatedHeader(offset: offset, available: data.count - offset)
        }
        // Parse fields with bounds checking...
    }
}
```

### 1.2 Load Commands

Load commands immediately follow the header. Each starts with:

```c
struct load_command {
    uint32_t cmd;      // Command type (LC_SEGMENT_64, LC_SYMTAB, etc.)
    uint32_t cmdsize;  // Total size including variable-length data
};
```

**Critical Load Commands for Binary Analysis:**

| Command | Value | Purpose |
|---------|-------|---------|
| `LC_SEGMENT_64` | 0x19 | 64-bit memory segment definition |
| `LC_SYMTAB` | 0x02 | Symbol table location |
| `LC_DYSYMTAB` | 0x0B | Dynamic symbol table info |
| `LC_LOAD_DYLIB` | 0x0C | Dynamically linked library |
| `LC_CODE_SIGNATURE` | 0x1D | Code signature location |
| `LC_FUNCTION_STARTS` | 0x26 | Compressed function start addresses |
| `LC_MAIN` | 0x80000028 | Entry point for main executables |
| `LC_BUILD_VERSION` | 0x32 | Build version and SDK info |

### 1.3 LC_SEGMENT_64 Structure

```c
struct segment_command_64 {
    uint32_t  cmd;          // LC_SEGMENT_64
    uint32_t  cmdsize;      // sizeof(segment_command_64) + sizeof(section_64) * nsects
    char      segname[16];  // Segment name (__TEXT, __DATA, __LINKEDIT)
    uint64_t  vmaddr;       // Virtual memory address
    uint64_t  vmsize;       // Virtual memory size
    uint64_t  fileoff;      // File offset
    uint64_t  filesize;     // File size
    vm_prot_t maxprot;      // Maximum VM protection
    vm_prot_t initprot;     // Initial VM protection
    uint32_t  nsects;       // Number of sections
    uint32_t  flags;        // Segment flags
};
```

**Common Segments:**

- **`__PAGEZERO`**: Null pointer trap (no read/write/execute)
- **`__TEXT`**: Executable code and read-only data
- **`__DATA`**: Writable data
- **`__DATA_CONST`**: Constant data (writable during launch, then read-only)
- **`__LINKEDIT`**: Symbol tables, code signatures, other linker data

**Page Alignment**: ARM64 macOS uses 16 KiB (0x4000) page alignment.

### 1.4 Fat/Universal Binary Handling

Fat binaries contain multiple architecture slices. Header starts with magic `0xCAFEBABE`:

```c
struct fat_header {
    uint32_t magic;     // FAT_MAGIC = 0xCAFEBABE (big-endian!)
    uint32_t nfat_arch; // Number of architecture slices
};

struct fat_arch {
    cpu_type_t    cputype;    // CPU_TYPE_ARM64 = 0x0100000C
    cpu_subtype_t cpusubtype; // CPU_SUBTYPE_ARM64E, etc.
    uint32_t      offset;     // Offset to Mach-O in file
    uint32_t      size;       // Size of Mach-O
    uint32_t      align;      // Alignment (power of 2)
};
```

**Important**: Fat headers are **big-endian**, unlike the little-endian Mach-O headers.

**Swift Implementation:**
```swift
struct FatBinary: Sendable {
    let architectures: [FatArch]

    func slice(for cpuType: CPUType, subtype: CPUSubtype? = nil) -> FatArch? {
        architectures.first { arch in
            arch.cpuType == cpuType && (subtype == nil || arch.cpuSubtype == subtype)
        }
    }
}
```

### 1.5 Code Signature Parsing

Code signatures are located via `LC_CODE_SIGNATURE` and use a SuperBlob container:

```
SuperBlob (magic: 0xFADE0CC0)
├── CodeDirectory (magic: 0xFADE0C02) - Main signature data
│   ├── Identifier (bundle ID)
│   ├── Team ID
│   ├── Page hashes (4KB pages of __TEXT)
│   └── Special slot hashes
├── Requirements (magic: 0xFADE0C01)
├── Entitlements (magic: 0xFADE7171) - XML plist
├── DER Entitlements (magic: 0xFADE7172) - Binary format
└── CMS Signature (magic: 0xFADE0B01)
```

**Key Points:**
- All blob data is **big-endian**
- CDHash (hash of CodeDirectory) is the ultimate binary identifier
- Entitlements are embedded as XML plist or DER-encoded

**Parsing Approach:**
```swift
enum CodeSignatureBlob {
    case codeDirectory(CodeDirectory)
    case requirements(Data)
    case entitlements(String)  // XML plist
    case derEntitlements(Data)
    case cmsSignature(Data)

    init(magic: UInt32, data: Data) throws {
        switch magic {
        case 0xFADE0C02: self = .codeDirectory(try CodeDirectory(from: data))
        case 0xFADE7171: self = .entitlements(String(data: data, encoding: .utf8) ?? "")
        // ...
        }
    }
}
```

### 1.6 Sources

- [Mach-O Wikipedia](https://en.wikipedia.org/wiki/Mach-O)
- [Anatomy of a Mach-O - Olivia Gallucci](https://oliviagallucci.com/the-anatomy-of-a-mach-o-structure-code-signing-and-pac/)
- [Exploring Mach-O - gpanders](https://gpanders.com/blog/exploring-mach-o-part-1/)
- [Low Level Bits - Parsing Mach-O](https://lowlevelbits.org/parsing-mach-o-files/)
- [GitHub - OSX ABI Mach-O Reference](https://github.com/aidansteele/osx-abi-macho-file-format-reference)
- [llios LC_CODE_SIGNATURE docs](https://github.com/qyang-nj/llios/blob/main/macho_parser/docs/LC_CODE_SIGNATURE.md)
- [HackTricks - macOS Code Signing](https://book.hacktricks.wiki/en/macos-hardening/macos-security-and-privilege-escalation/macos-security-protections/macos-code-signing.html)
- [Universal Binaries Deep Dive](https://www.jviotti.com/2021/07/23/a-deep-dive-on-macos-universal-binaries.html)

---

## 2. ARM64 Disassembly

### 2.1 Instruction Encoding

ARM64 (AArch64) instructions are **fixed 32-bit width**, making decoding straightforward:

```
┌─────────────────────────────────────────────────────┐
│  31  28 │ 27  25 │ 24  21 │  20  16 │ 15   0       │
│   op0   │  op1   │  op2   │   ...   │  operands    │
└─────────────────────────────────────────────────────┘
```

**Encoding Categories:**
- Data Processing (Immediate/Register)
- Branches
- Loads and Stores
- SIMD/FP
- System instructions

There are approximately **442 instruction mnemonics** organized in a hierarchical encoding table.

### 2.2 Pointer Authentication (PAC)

Apple Silicon implements ARMv8.3 Pointer Authentication:

| Instruction | Purpose |
|-------------|---------|
| `PACIA` | Sign instruction pointer with A key |
| `PACIB` | Sign instruction pointer with B key |
| `PACDA` | Sign data pointer with A key |
| `AUTIA` | Authenticate instruction pointer (A key) |
| `AUTIB` | Authenticate instruction pointer (B key) |
| `BRAA` | Authenticated branch (A key) |
| `RETAB` | Authenticated return (B key) |

**Implementation Note**: PAC instructions are in NOP-space for backward compatibility. On older CPUs, they execute as NOPs.

**Detecting PAC in binaries:**
```swift
func isPACInstruction(_ instruction: UInt32) -> Bool {
    // PAC instructions use hint space: bits [31:24] = 0b11010101
    // with specific patterns for each PAC operation
    let hintMask: UInt32 = 0xFF00_0000
    let hintPattern: UInt32 = 0xD500_0000
    return (instruction & hintMask) == hintPattern
}
```

### 2.3 Apple AMX Instructions

Apple's **undocumented** matrix coprocessor (AMX) is distinct from Intel AMX:

- Executed on a separate accelerator unit
- Uses special `amx*` encoding space
- 32x32 grid of compute units
- Used by Accelerate.framework for matrix operations

**Note**: AMX is undocumented and changes between chip generations (M1/M2/M3/M4). Disassembly should recognize but not depend on these instructions.

Reference: [GitHub - corsix/amx](https://github.com/corsix/amx)

### 2.4 Swift Calling Convention (ARM64)

Swift uses a modified ARM64 calling convention:

| Register | Purpose |
|----------|---------|
| x0-x7 | Integer arguments / return value |
| x8 | Indirect result location (struct return) |
| x9-x15 | Temporary registers |
| x16-x17 | Intra-procedure scratch (IP0/IP1) |
| x18 | Platform reserved |
| x19-x28 | Callee-saved registers |
| x20 | **Swift context register (self)** |
| x21 | **Swift error return** |
| x29 | Frame pointer (FP) |
| x30 | Link register (LR) |
| sp | Stack pointer (16-byte aligned) |
| v0-v7 | SIMD/FP arguments |

**Key Difference from Standard AAPCS64**: Swift packs multiple small arguments into single registers.

Reference: [Swift ABI - Calling Convention](https://github.com/swiftlang/swift/blob/main/docs/ABI/CallingConvention.rst)

### 2.5 Capstone vs Custom Disassembler

**Capstone Advantages:**
- Mature, battle-tested (~3000 ARM64 encodings)
- Swift bindings available: [zydeco/capstone-swift](https://github.com/zydeco/capstone-swift)
- Handles edge cases and pseudo-instructions
- Semantic information (register reads/writes, instruction groups)

**Custom Disassembler Advantages:**
- No external dependency (aligns with constitution)
- Full control over output format
- Can be optimized for specific use case (e.g., only common instructions)
- Swift-native error handling

**Recommendation**: Start with custom disassembler for core ARM64 instructions (covers ~80% of cases), with optional Capstone integration for complete coverage. This aligns with the "no external dependencies unless necessary" principle.

```swift
// Minimal custom decoder
struct ARM64Instruction: Sendable {
    let address: UInt64
    let encoding: UInt32
    let mnemonic: String
    let operands: [Operand]

    static func decode(_ encoding: UInt32, at address: UInt64) -> ARM64Instruction {
        // Hierarchical decoding based on bits [28:25]
        let op0 = (encoding >> 25) & 0xF
        switch op0 {
        case 0b1000, 0b1001: return decodeDataProcessingImm(encoding, at: address)
        case 0b1010, 0b1011: return decodeBranch(encoding, at: address)
        case 0b0100, 0b0110, 0b1100, 0b1110: return decodeLoadStore(encoding, at: address)
        // ...
        }
    }
}
```

### 2.6 Sources

- [ARM A64 Instruction Set Encoding](https://developer.arm.com/documentation/ddi0602/latest/Index-by-Encoding)
- [Binary Ninja - Ground-up AArch64](https://binary.ninja/2021/04/05/groundup-aarch64.html)
- [Apple - Writing ARM64 Code](https://developer.apple.com/documentation/xcode/writing-arm64-code-for-apple-platforms)
- [Visualizing ARM64 Instruction Set](https://zyedidia.github.io/blog/posts/6-arm64/)
- [Swift ABI - Register Usage](https://github.com/swiftlang/swift/blob/main/docs/ABI/CallingConvention.rst)
- [ARM64 Instruction Decoding - ipsw](https://deepwiki.com/blacktop/ipsw/10.2-arm64-instruction-decoding)

---

## 3. Debugger Implementation

### 3.1 ptrace on macOS

macOS ptrace is limited compared to Linux:

```c
// Available ptrace requests
PT_TRACE_ME      // Allow parent to trace
PT_ATTACHEXC     // Attach with Mach exception delivery (preferred)
PT_DETACH        // Detach from process
PT_STEP          // Single step
PT_CONTINUE      // Continue execution
PT_KILL          // Terminate process
PT_DENY_ATTACH   // Anti-debug (can be bypassed with Mach APIs)
```

**Important**: `PT_ATTACHEXC` delivers events as Mach exceptions, not UNIX signals. This is the modern approach.

### 3.2 task_for_pid and Mach APIs

The core debugging APIs on macOS are Mach-based:

```swift
import Darwin

func getTaskPort(for pid: pid_t) throws -> mach_port_t {
    var task: mach_port_t = 0
    let kr = task_for_pid(mach_task_self_, pid, &task)
    guard kr == KERN_SUCCESS else {
        throw DebuggerError.taskForPidFailed(kernReturn: kr)
    }
    return task
}
```

**Key Mach Functions:**

| Function | Purpose |
|----------|---------|
| `task_for_pid()` | Get task port (requires entitlement) |
| `vm_read()` / `vm_write()` | Read/write target memory |
| `thread_get_state()` | Read registers |
| `thread_set_state()` | Modify registers |
| `task_set_exception_ports()` | Install exception handler |
| `mach_port_allocate()` | Create exception port |

### 3.3 Exception Handling for Breakpoints

Setting up Mach exception handling:

```swift
func setupExceptionHandler(for task: mach_port_t) throws -> mach_port_t {
    var exceptionPort: mach_port_t = 0

    // Allocate port with receive right
    var kr = mach_port_allocate(
        mach_task_self_,
        MACH_PORT_RIGHT_RECEIVE,
        &exceptionPort
    )
    guard kr == KERN_SUCCESS else { throw DebuggerError.portAllocationFailed }

    // Add send right
    kr = mach_port_insert_right(
        mach_task_self_,
        exceptionPort,
        exceptionPort,
        MACH_MSG_TYPE_MAKE_SEND
    )
    guard kr == KERN_SUCCESS else { throw DebuggerError.portInsertFailed }

    // Set exception port for breakpoints
    kr = task_set_exception_ports(
        task,
        exception_mask_t(EXC_MASK_BREAKPOINT),
        exceptionPort,
        EXCEPTION_DEFAULT | MACH_EXCEPTION_CODES,
        ARM_THREAD_STATE64
    )
    guard kr == KERN_SUCCESS else { throw DebuggerError.setExceptionPortsFailed }

    return exceptionPort
}
```

### 3.4 Hardware Breakpoints on Apple Silicon

ARM64 provides up to 16 hardware breakpoints and 16 watchpoints:

**Debug Registers:**
- `DBGBVR<n>_EL1`: Breakpoint Value Registers (address)
- `DBGBCR<n>_EL1`: Breakpoint Control Registers
- `DBGWVR<n>_EL1`: Watchpoint Value Registers
- `DBGWCR<n>_EL1`: Watchpoint Control Registers

Access via `thread_get_state()` with `ARM_DEBUG_STATE64`:

```swift
func setHardwareBreakpoint(
    thread: thread_t,
    address: UInt64,
    index: Int
) throws {
    var debugState = arm_debug_state64_t()
    var count = mach_msg_type_number_t(ARM_DEBUG_STATE64_COUNT)

    // Get current debug state
    var kr = thread_get_state(
        thread,
        ARM_DEBUG_STATE64,
        &debugState,
        &count
    )
    guard kr == KERN_SUCCESS else { throw DebuggerError.getStateFailed }

    // Set breakpoint address and enable
    withUnsafeMutablePointer(to: &debugState.__bvr) { bvr in
        bvr[index] = address
    }
    withUnsafeMutablePointer(to: &debugState.__bcr) { bcr in
        // Enable, match any EL, byte address select all
        bcr[index] = 0x1E5  // Enabled, EL0/EL1, address match
    }

    kr = thread_set_state(thread, ARM_DEBUG_STATE64, &debugState, count)
    guard kr == KERN_SUCCESS else { throw DebuggerError.setStateFailed }
}
```

### 3.5 Required Entitlements

**For the debugger binary:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.debugger</key>
    <true/>
</dict>
</plist>
```

**For target binaries (development builds):**
```xml
<key>com.apple.security.get-task-allow</key>
<true/>
```

**Relationship:**
- Debugger needs `com.apple.security.cs.debugger` to call `task_for_pid()`
- Target needs `get-task-allow` to be debuggable (unless running as root)
- System binaries protected by SIP cannot be debugged

### 3.6 SIP Considerations

System Integrity Protection restricts:
- Debugging of system processes
- Modification of protected directories
- Loading unsigned kernel extensions

**Graceful Degradation Approach:**
```swift
enum DebuggingCapability: Sendable {
    case full                    // All permissions available
    case userProcessesOnly       // Can debug user apps with get-task-allow
    case readOnly                // Can only inspect, not attach
    case none                    // No debugging capability

    static func detect() -> DebuggingCapability {
        // Check if we have debugger entitlement
        // Check if SIP allows task_for_pid
        // Return appropriate capability level
    }
}
```

### 3.7 Sources

- [SpaceFlint - Using ptrace on OS X](https://www.spaceflint.com/?p=150)
- [Apple Developer Forums - Debug process by hand](https://developer.apple.com/forums/thread/741137)
- [ldpreload - macOS Debugger](https://ldpreload.com/p/osx-debugger.html)
- [Machium Debugger](https://psychobird.github.io/Machium/Machium.html)
- [Darling Docs - Mach Exceptions](https://docs.darlinghq.org/internals/macos-specifics/mach-exceptions.html)
- [HackTricks - Dangerous Entitlements](https://book.hacktricks.wiki/en/macos-hardening/macos-security-and-privilege-escalation/macos-security-protections/macos-dangerous-entitlements.html)
- [Apple - Debugging Tool Entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.debugger)
- [ARM Debug Architecture](https://documentation-service.arm.com/static/63f75e6c7741343f18b6d44f)

---

## 4. Swift 6.2 Features

### 4.1 Approachable Concurrency

Swift 6.2 (released September 15, 2025) simplifies concurrency:

**Default Main Actor Isolation:**
```swift
// With new compiler flag, functions are MainActor by default
func parseHeader() async throws -> MachHeader64 {
    // Runs on main thread unless marked @concurrent
}

@concurrent
func disassembleFunction(at address: UInt64) async throws -> [ARM64Instruction] {
    // Explicitly runs on global concurrent executor
}
```

**Async Inherits Caller Context:**
```swift
// In Swift 6.2, async functions run in caller's context
actor BinaryAnalyzer {
    func analyze() async {
        let result = await helper()  // helper runs on this actor
    }

    func helper() async -> Result { ... }
}
```

### 4.2 Strict Memory Safety

Opt-in mode that flags all unsafe operations:

```bash
swiftc -strict-memory-safety ...
```

**New Attributes:**
```swift
@unsafe
func parseWithUnsafePointer<T>(_ data: Data) -> T {
    data.withUnsafeBytes { $0.load(as: T.self) }
}

// Call site must acknowledge unsafe
let header = unsafe parseWithUnsafePointer(data)
```

### 4.3 Span Type for Safe Memory Access

`Span<T>` is the safe replacement for `UnsafeBufferPointer<T>`:

```swift
// Old (unsafe)
data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
    let value = buffer.load(fromByteOffset: offset, as: UInt32.self)
}

// New (safe with Span)
func parse(span: Span<UInt8>) throws -> UInt32 {
    guard span.count >= 4 else { throw ParseError.insufficientData }
    // Bounds-checked access
    return span.withUnsafeBytes { $0.load(as: UInt32.self) }
}
```

**Key Properties:**
- Non-escaping (lifetime-safe)
- Bounds-checked at runtime
- No overhead vs unsafe pointers
- Interoperates with C++ `std::span`

### 4.4 Memory-Mapped Files in Swift

**Using Foundation:**
```swift
let data = try Data(
    contentsOf: url,
    options: .mappedIfSafe  // Uses mmap when safe
)
```

**Direct mmap for Control:**
```swift
final class MemoryMappedFile: @unchecked Sendable {
    private let pointer: UnsafeRawPointer
    private let size: Int
    private let fileDescriptor: Int32

    init(path: String) throws {
        fileDescriptor = open(path, O_RDONLY)
        guard fileDescriptor >= 0 else {
            throw MappingError.openFailed(errno: errno)
        }

        var stat = stat()
        guard fstat(fileDescriptor, &stat) == 0 else {
            close(fileDescriptor)
            throw MappingError.statFailed(errno: errno)
        }

        size = Int(stat.st_size)
        guard let mapped = mmap(nil, size, PROT_READ, MAP_PRIVATE, fileDescriptor, 0),
              mapped != MAP_FAILED else {
            close(fileDescriptor)
            throw MappingError.mmapFailed(errno: errno)
        }

        pointer = UnsafeRawPointer(mapped)
    }

    deinit {
        munmap(UnsafeMutableRawPointer(mutating: pointer), size)
        close(fileDescriptor)
    }

    func bytes(at offset: Int, count: Int) throws -> Span<UInt8> {
        guard offset >= 0, offset + count <= size else {
            throw MappingError.outOfBounds(offset: offset, count: count, size: size)
        }
        // Return span with bounds checking
        return Span(unsafeStart: pointer.advanced(by: offset), count: count)
    }
}
```

### 4.5 C Interop for System Calls

```swift
// Importing Darwin provides mach_*, ptrace, etc.
import Darwin

// Type-safe wrapper
enum MachError: Error {
    case kernelError(kern_return_t)

    static func check(_ kr: kern_return_t) throws {
        guard kr == KERN_SUCCESS else {
            throw MachError.kernelError(kr)
        }
    }
}

// Usage
let task = try MachError.check(task_for_pid(mach_task_self_, pid, &taskPort))
```

### 4.6 Sources

- [Swift 6.2 Released - Swift.org](https://www.swift.org/blog/swift-6.2-released/)
- [What's New in Swift 6.2 - Hacking with Swift](https://www.hackingwithswift.com/articles/277/whats-new-in-swift-6-2)
- [Approachable Concurrency Guide - SwiftLee](https://www.avanderlee.com/concurrency/approachable-concurrency-in-swift-6-2-a-clear-guide/)
- [SE-0447 Span Proposal](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0447-span-access-shared-contiguous-storage.md)
- [SE-0458 Strict Memory Safety](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0458-strict-memory-safety.md)
- [Swift Forums - Memory Mapping](https://forums.swift.org/t/what-s-the-recommended-way-to-memory-map-a-file/19113)

---

## 5. macOS Tahoe 26 Security

### 5.1 Platform Overview

macOS Tahoe (version 26) released September 15, 2025:
- Final version supporting Intel Macs
- Enhanced code-signing restrictions
- Background security updates (26.3+)

### 5.2 Developer Tool Permissions

**System Settings > Privacy & Security:**

1. **Developer Tools**: Required for running unsigned code
2. **Full Disk Access**: For analyzing protected files
3. **Accessibility**: Not typically required for binary analysis

**Programmatic Detection:**
```swift
enum PrivacyPermission: Sendable {
    case developerTools
    case fullDiskAccess

    var isGranted: Bool {
        switch self {
        case .developerTools:
            // Check if we can execute unsigned code
            return checkDevToolsAccess()
        case .fullDiskAccess:
            // Try accessing a protected path
            return FileManager.default.isReadableFile(atPath: "/Library/Application Support/com.apple.TCC/TCC.db")
        }
    }

    var systemSettingsPath: String {
        switch self {
        case .developerTools:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_DevTools"
        case .fullDiskAccess:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        }
    }
}
```

### 5.3 Endpoint Security Framework

ES is required for monitoring system events, but **not required for static binary analysis**.

**When ES is Needed:**
- Monitoring process execution
- File access auditing
- Real-time behavioral analysis

**When ES is NOT Needed:**
- Parsing Mach-O files from disk
- Static disassembly
- Reading code signatures

**Entitlement Required:**
```xml
<key>com.apple.developer.endpoint-security.client</key>
<true/>
```

### 5.4 Hardened Runtime

macOS Tahoe enforces hardened runtime for notarized apps:

**Relevant Capabilities:**
```xml
<!-- Allow JIT for disassembly engine if needed -->
<key>com.apple.security.cs.allow-jit</key>
<true/>

<!-- Allow unsigned executable memory -->
<key>com.apple.security.cs.allow-unsigned-executable-memory</key>
<true/>

<!-- Allow loading third-party libraries -->
<key>com.apple.security.cs.disable-library-validation</key>
<true/>
```

**Recommendation**: Avoid these entitlements if possible. Our pure Swift approach should not require JIT or unsigned memory.

### 5.5 New in macOS 26.1+

Starting with macOS 26.1:
- Processor Trace Instrument works with ad-hoc signed code
- Relaxed `get-task-allow` requirement for some debugging scenarios

### 5.6 Sources

- [macOS Tahoe Wikipedia](https://en.wikipedia.org/wiki/MacOS_Tahoe)
- [SecureMac - Tahoe Security Guide](https://www.securemac.com/news/macos-tahoe-26-security-and-privacy-guide)
- [Apple - Tahoe 26.2 Release Notes](https://developer.apple.com/documentation/macos-release-notes/macos-26_2-release-notes)
- [Apple - Endpoint Security](https://developer.apple.com/documentation/endpointsecurity)
- [newosxbook - Endpoint Security](https://newosxbook.com/articles/eps.html)
- [WWDC20 - Build an Endpoint Security app](https://developer.apple.com/videos/play/wwdc2020/10159/)

---

## 6. Metal GPU Acceleration Evaluation

### 6.1 Potential Use Cases

| Use Case | Benefit | Feasibility |
|----------|---------|-------------|
| Pattern matching in large binaries | Parallel string/byte search | Medium |
| Parallel disassembly | Multiple functions simultaneously | Low |
| Signature scanning | YARA-like rule matching | Medium |
| Entropy analysis | Block-level entropy calculation | High |

### 6.2 Analysis

**Arguments FOR Metal:**
- GPUs excel at data-parallel operations
- Pattern matching maps well to SIMD
- Large binaries (100MB+) could benefit

**Arguments AGAINST Metal:**
- Binary analysis is largely sequential (dependencies between instructions)
- Instruction decoding requires complex branching (poor GPU fit)
- Memory transfer overhead may exceed computation savings
- Adds significant complexity and dependency

### 6.3 Performance Characteristics

From research:
- GPU ideal for high arithmetic intensity (many ops per memory transfer)
- Binary analysis is memory-bound, not compute-bound
- Disassembly involves irregular branching patterns
- Most binaries fit in CPU cache for fast sequential access

### 6.4 Recommendation: EXCLUDE Metal

**Rationale:**
1. **Complexity vs Benefit**: Binary analysis workloads don't match GPU strengths
2. **Constitution Alignment**: "No external dependencies unless absolutely necessary"
3. **Sequential Nature**: Disassembly and parsing are inherently sequential
4. **Memory Bound**: Binary analysis is limited by memory access, not computation
5. **Edge Cases**: GPU scheduling overhead would dominate for typical binary sizes

**Alternative Optimizations:**
- Swift concurrency for parallel function disassembly
- Memory-mapped files for efficient I/O
- Lazy parsing to avoid unnecessary work
- SIMD intrinsics for specific byte searches (via Swift)

### 6.5 Sources

- [Apple - Metal Performance Shaders](https://developer.apple.com/documentation/metalperformanceshaders)
- [WWDC16 - Advanced Metal Shader Optimization](https://developer.apple.com/videos/play/wwdc2016/606/)
- [Metal Compute Shaders - neurolabusc](https://github.com/neurolabusc/Metal)
- [GPGPU Wikipedia](https://en.wikipedia.org/wiki/General-purpose_computing_on_graphics_processing_units)

---

## 7. Implementation Recommendations

### 7.1 Architecture Overview

```
MachScope/
├── Sources/
│   ├── MachOParser/           # Mach-O parsing (standalone library)
│   │   ├── MachHeader.swift
│   │   ├── LoadCommands.swift
│   │   ├── Segments.swift
│   │   ├── CodeSignature.swift
│   │   └── FatBinary.swift
│   │
│   ├── ARM64Disassembler/     # Disassembly engine
│   │   ├── Decoder.swift
│   │   ├── Instructions/
│   │   │   ├── DataProcessing.swift
│   │   │   ├── Branch.swift
│   │   │   ├── LoadStore.swift
│   │   │   └── System.swift
│   │   └── Formatter.swift
│   │
│   ├── Debugger/              # Runtime debugging
│   │   ├── MachDebugger.swift
│   │   ├── Breakpoints.swift
│   │   ├── Registers.swift
│   │   └── Entitlements.swift
│   │
│   └── MachScopeCLI/          # Thin CLI layer
│       └── main.swift
│
└── Tests/
    ├── MachOParserTests/
    ├── ARM64DisassemblerTests/
    └── Fixtures/              # Known binaries for testing
```

### 7.2 Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Disassembler | Custom (core) | No dependencies, Swift-native errors |
| Memory mapping | mmap for >10MB | Performance for large binaries |
| Parsing | Lazy on-demand | Memory efficiency |
| Error handling | Typed Swift errors | Precise, recoverable errors |
| Concurrency | Swift 6.2 actors | Built-in safety |
| Metal | Excluded | Poor fit for workload |
| Capstone | Optional future | Only if complete coverage needed |

### 7.3 Testing Strategy

**Unit Tests:**
- Parse known Mach-O headers
- Decode known ARM64 instruction patterns
- Validate code signature extraction

**Integration Tests:**
- Full parse → disassemble → output pipelines
- Fat binary slice extraction
- Error handling for malformed inputs

**Test Fixtures:**
- Include small known-good binaries in repo
- Include intentionally malformed binaries
- Never depend on system binaries

### 7.4 Permission Handling Flow

```swift
enum AnalysisMode: Sendable {
    case staticAnalysis    // No special permissions
    case processInspection // Needs task_for_pid
    case debugging         // Needs debugger entitlement + get-task-allow on target

    func checkAvailability() -> PermissionResult {
        switch self {
        case .staticAnalysis:
            return .available
        case .processInspection:
            return checkTaskForPidCapability()
        case .debugging:
            return checkDebuggerEntitlement()
        }
    }
}

func run(mode: AnalysisMode) async throws {
    switch mode.checkAvailability() {
    case .available:
        try await performAnalysis(mode: mode)
    case .unavailable(let reason, let guidance):
        print("Mode \(mode) unavailable: \(reason)")
        print("To enable: \(guidance)")
        // Fall back to lower capability mode
        try await run(mode: mode.fallback)
    }
}
```

### 7.5 Swift Runtime Metadata Parsing

For reverse engineering Swift binaries:

**Key Segments:**
- `__swift5_typeref`: Type references
- `__swift5_fieldmd`: Field metadata
- `__swift5_types`: Type descriptors
- `__swift5_proto`: Protocol descriptors

**Relative Pointer Decoding:**
```swift
func resolveRelativePointer(at address: UInt64, in data: Data) -> UInt64? {
    guard let offset = readInt32(at: address, in: data) else { return nil }
    return address + UInt64(bitPattern: Int64(offset))
}
```

Reference: [Swift ABI - TypeMetadata.rst](https://github.com/apple/swift/blob/main/docs/ABI/TypeMetadata.rst)

---

## Appendix A: Quick Reference

### Mach-O Magic Numbers

| Magic | Meaning |
|-------|---------|
| `0xFEEDFACE` | 32-bit Mach-O |
| `0xFEEDFACF` | 64-bit Mach-O |
| `0xCAFEBABE` | Fat binary (big-endian) |
| `0xBEBAFECA` | Fat binary (little-endian swap) |

### ARM64 CPU Types

| Type | Value |
|------|-------|
| `CPU_TYPE_ARM64` | 0x0100000C |
| `CPU_SUBTYPE_ARM64_ALL` | 0 |
| `CPU_SUBTYPE_ARM64E` | 2 |

### Code Signature Magics

| Magic | Blob Type |
|-------|-----------|
| `0xFADE0CC0` | SuperBlob |
| `0xFADE0C02` | CodeDirectory |
| `0xFADE0C01` | Requirements |
| `0xFADE7171` | Entitlements (XML) |
| `0xFADE7172` | DER Entitlements |
| `0xFADE0B01` | CMS Signature |

---

**Document Version**: 1.0
**Last Updated**: 2026-01-12
