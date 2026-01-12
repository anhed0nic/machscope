# Feature Specification: MachScope Binary Analysis Tool

**Feature Branch**: `001-macos-binary-analysis`
**Created**: 2026-01-12
**Status**: Draft
**Input**: User description: "Build MachScope - a native macOS Binary Analysis Tool with Mach-O Parser, ARM64 Disassembler, and Simple Debugger components"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Parse Mach-O Binary Structure (Priority: P1)

A security researcher wants to understand the structure of a macOS executable. They run MachScope against a binary file to see its headers, load commands, segments, sections, and embedded metadata without needing to remember complex command-line flags or use multiple tools.

**Why this priority**: Parsing is the foundation for all other functionality. Without accurate Mach-O parsing, disassembly and debugging cannot function. This delivers immediate value as a standalone capability.

**Independent Test**: Can be fully tested by parsing any macOS binary (e.g., `/bin/ls`) and verifying the output matches expected structure. Delivers value as a complete binary inspection tool.

**Acceptance Scenarios**:

1. **Given** a valid Mach-O executable, **When** user runs `machscope parse /path/to/binary`, **Then** system displays header information (magic, CPU type, file type, flags), all load commands with their types and parameters, segment names with addresses and sizes, and section details.

2. **Given** a Fat/Universal binary containing multiple architectures, **When** user runs `machscope parse /path/to/universal`, **Then** system lists all contained architectures and parses the arm64 slice by default, with option to select a specific architecture.

3. **Given** a binary with code signature, **When** user runs `machscope parse /path/to/signed --signatures`, **Then** system displays code signature information including team ID, signing identity, entitlements (if present), and CDHash.

4. **Given** user requests JSON output, **When** user runs `machscope parse /path/to/binary --json`, **Then** system outputs all parsed data in valid JSON format suitable for scripting and automation.

---

### User Story 2 - Disassemble ARM64 Code (Priority: P2)

A reverse engineer wants to examine the assembly code of a specific function in a macOS binary. They use MachScope to disassemble the binary's executable sections, with symbols resolved to meaningful names and special instructions (like PAC) highlighted.

**Why this priority**: Disassembly builds on parsing and is the second most common binary analysis task. It enables understanding program behavior without source code.

**Independent Test**: Can be fully tested by disassembling a known binary and verifying instruction mnemonics and operands match expected output. Delivers value for code analysis.

**Acceptance Scenarios**:

1. **Given** a valid ARM64 Mach-O binary, **When** user runs `machscope disasm /path/to/binary`, **Then** system displays disassembled instructions for all executable sections with addresses, raw bytes, mnemonics, and operands.

2. **Given** a binary with symbol table, **When** user runs `machscope disasm /path/to/binary --function main`, **Then** system disassembles only the specified function, showing its boundaries and annotating calls to other functions with their symbol names.

3. **Given** code containing pointer authentication instructions, **When** disassembling such code, **Then** system highlights PAC instructions (PACIA, AUTIA, BRAA, etc.) with annotations explaining their security purpose.

4. **Given** a Swift binary, **When** disassembling functions, **Then** system annotates Swift-specific patterns such as witness table lookups, metadata access, and demangled Swift symbol names where identifiable.

5. **Given** a branch or call instruction, **When** the target address corresponds to a known symbol, **Then** system displays the symbol name alongside the numeric address.

---

### User Story 3 - Check System Permissions (Priority: P3)

A user installing MachScope for the first time wants to verify they have the necessary permissions for all features. They run a permissions check command that tells them exactly what's available and what needs to be enabled.

**Why this priority**: Permission handling is essential for user experience but not core functionality. Users need clear guidance to enable debugging features.

**Independent Test**: Can be fully tested by running the check on a clean system and verifying accurate detection of permission states.

**Acceptance Scenarios**:

1. **Given** a fresh installation, **When** user runs `machscope check-permissions`, **Then** system displays current permission status for: Developer Tools access, debugger entitlement validity, SIP (System Integrity Protection) status, and Full Disk Access (if needed).

2. **Given** missing Developer Tools permission, **When** running check-permissions, **Then** system provides specific instructions: "Open System Settings > Privacy & Security > Developer Tools and enable [Terminal/MachScope]".

3. **Given** SIP is enabled, **When** user attempts to use debugging features on system binaries, **Then** system warns that system binaries cannot be debugged with SIP enabled and suggests targeting user binaries instead.

---

### User Story 4 - Debug Running Process (Priority: P4)

An advanced user wants to attach to a running process to inspect its runtime state, set breakpoints, and step through execution. They use MachScope's debugger to attach to a process they have permission to debug.

**Why this priority**: Debugging is the most complex feature with the most permission requirements. It builds on all previous functionality and is optional for users who only need static analysis.

**Independent Test**: Can be tested by attaching to a simple test program, setting a breakpoint, hitting it, and reading register values.

**Acceptance Scenarios**:

1. **Given** a running process with get-task-allow entitlement, **When** user runs `machscope debug <pid>`, **Then** system attaches to the process and enters interactive debug mode showing current instruction pointer and basic register state.

2. **Given** attached to a process, **When** user sets a breakpoint at an address or symbol, **Then** system installs a software breakpoint and reports success with the breakpoint ID.

3. **Given** a breakpoint is hit, **When** execution stops, **Then** system displays the current address, disassembled instruction, and allows user to inspect registers and memory.

4. **Given** user wants to step execution, **When** user issues step command, **Then** system executes one instruction and stops, displaying the new state.

5. **Given** insufficient permissions to attach, **When** user attempts `machscope debug <pid>`, **Then** system displays clear error explaining the permission issue and how to resolve it (e.g., "Target process lacks get-task-allow entitlement" or "Run as root or enable Developer Tools").

---

### User Story 5 - Export Symbol and String Data (Priority: P5)

A malware analyst wants to extract all strings and symbols from a suspicious binary for further analysis in other tools. They export this data in JSON format for automated processing.

**Why this priority**: Data export extends the utility of parsing for integration with other tools and workflows.

**Independent Test**: Can be tested by exporting symbols/strings and validating JSON structure and content completeness.

**Acceptance Scenarios**:

1. **Given** a binary with symbol table, **When** user runs `machscope parse /path/to/binary --symbols --json`, **Then** system outputs all symbols with their names, addresses, types, and visibility in JSON format.

2. **Given** a binary with embedded strings, **When** user runs `machscope parse /path/to/binary --strings --json`, **Then** system outputs all null-terminated strings found in data sections with their addresses and section names.

---

### Edge Cases

- What happens when user provides a path to a non-Mach-O file (e.g., ELF, PE, or text file)?
  - System MUST detect invalid format and display clear error: "Not a valid Mach-O binary: [reason]"

- What happens when parsing a corrupted or truncated binary?
  - System MUST handle gracefully, displaying whatever data can be parsed and noting which sections failed

- What happens when disassembling very large binaries (100MB+)?
  - System MUST use memory-mapped access and show progress indication for long operations

- What happens when attempting to debug a process protected by SIP?
  - System MUST detect and report: "Cannot debug [process]: protected by System Integrity Protection"

- What happens when the binary contains unknown or future ARM64 instructions?
  - System MUST display raw bytes with "unknown instruction" annotation rather than crashing

- What happens when a Fat binary has no arm64 slice?
  - System MUST list available architectures and inform user that no arm64 slice is present

## Requirements *(mandatory)*

### Functional Requirements

**Mach-O Parser:**

- **FR-001**: System MUST parse 64-bit Mach-O headers (magic number 0xFEEDFACF) and validate CPU type is ARM64
- **FR-002**: System MUST parse all standard load commands including LC_SEGMENT_64, LC_SYMTAB, LC_DYSYMTAB, LC_CODE_SIGNATURE, LC_MAIN, LC_LOAD_DYLIB, LC_BUILD_VERSION
- **FR-003**: System MUST parse segment and section structures, displaying names, virtual addresses, file offsets, and sizes
- **FR-004**: System MUST detect and parse Fat/Universal binaries (magic 0xCAFEBABE), listing all architectures and defaulting to arm64 slice
- **FR-005**: System MUST parse code signature SuperBlob structure, extracting CodeDirectory, entitlements (XML and DER), and CDHash
- **FR-006**: System MUST extract symbol table entries with names, addresses, and type information
- **FR-007**: System MUST extract null-terminated strings from __cstring and other string sections
- **FR-008**: System MUST support memory-mapped file access for binaries larger than 10MB to maintain performance
- **FR-009**: System MUST export all parsed data in JSON format when requested

**ARM64 Disassembler:**

- **FR-010**: System MUST decode ARM64 instructions to human-readable assembly notation
- **FR-011**: System MUST support common instruction categories: data processing, branches, loads/stores, and system instructions
- **FR-012**: System MUST identify function boundaries using symbol table information
- **FR-013**: System MUST highlight pointer authentication instructions (PAC family) with explanatory annotations
- **FR-014**: System MUST resolve branch and call targets to symbol names when available
- **FR-015**: System MUST demangle Swift symbol names and annotate Swift-specific patterns where identifiable
- **FR-016**: System MUST display unknown instructions as raw hex bytes without crashing

**Debugger (Optional Component):**

- **FR-017**: System MUST attach to running processes using the target's PID
- **FR-018**: System MUST set and remove software breakpoints at specified addresses
- **FR-019**: System MUST read process memory at specified addresses and lengths
- **FR-020**: System MUST write to process memory (when permitted)
- **FR-021**: System MUST single-step execution (one instruction at a time)
- **FR-022**: System MUST display ARM64 register state (x0-x30, sp, pc, cpsr)
- **FR-023**: System MUST gracefully handle permission denial with actionable error messages

**Permission Handling:**

- **FR-024**: System MUST detect Developer Tools permission status
- **FR-025**: System MUST validate its own entitlements for debugging capability
- **FR-026**: System MUST detect SIP status and warn when targeting protected binaries
- **FR-027**: System MUST provide specific System Settings paths for enabling required permissions

**Command-Line Interface:**

- **FR-028**: System MUST provide `parse` subcommand for Mach-O analysis
- **FR-029**: System MUST provide `disasm` subcommand for disassembly
- **FR-030**: System MUST provide `debug` subcommand for attaching debugger
- **FR-031**: System MUST provide `check-permissions` subcommand for permission verification
- **FR-032**: System MUST support `--help` flag showing usage for all commands
- **FR-033**: System MUST support `--json` flag for machine-readable output where applicable
- **FR-034**: System MUST display version information via `--version` flag

### Key Entities

- **MachOBinary**: Represents a parsed Mach-O file; contains header, load commands, segments, sections, symbols, and code signature data

- **LoadCommand**: Represents a single load command with its type, size, and type-specific payload

- **Segment**: Represents a memory segment with name, virtual address, file offset, size, and contained sections

- **Section**: Represents a section within a segment with name, address, size, and content type

- **Symbol**: Represents a symbol table entry with name, address, type (function/data/external), and visibility

- **CodeSignature**: Represents parsed code signature including team ID, CDHash, and entitlements

- **Instruction**: Represents a decoded ARM64 instruction with address, encoding, mnemonic, operands, and optional annotations

- **DebugSession**: Represents an active debugging session with attached process, breakpoints, and current execution state

- **Breakpoint**: Represents a set breakpoint with ID, address, original bytes, and enabled state

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can parse any valid Mach-O binary and view its complete structure in under 5 seconds for typical binaries (<50MB)

- **SC-002**: System correctly identifies 100% of standard load command types defined in Apple's public headers

- **SC-003**: Users can disassemble a function by name and see its complete instruction listing with symbol cross-references

- **SC-004**: System handles binaries up to 500MB without crashing or excessive memory usage (memory stays under 2x file size)

- **SC-005**: Permission check command accurately detects permission status in 100% of tested configurations

- **SC-006**: Error messages include actionable next steps in 100% of permission-related failures

- **SC-007**: Users new to binary analysis can successfully parse their first binary within 2 minutes of installation

- **SC-008**: JSON output from parse command can be consumed by standard JSON tools (jq, Python json module) without modification

- **SC-009**: Debugger can attach, set breakpoint, hit breakpoint, and read registers on a compliant test process within 30 seconds

- **SC-010**: System works correctly on macOS Tahoe 26.2 and later on Apple Silicon (arm64) Macs

## Assumptions

- Users have basic familiarity with command-line tools
- Target binaries are not encrypted (system does not handle Apple FairPlay DRM)
- Debugger target processes have appropriate entitlements (get-task-allow) unless user runs as root
- Network connectivity is not required (fully offline operation)
- Users understand that debugging system binaries requires disabling SIP (which is not recommended)
