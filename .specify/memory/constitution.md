<!--
  =============================================================================
  SYNC IMPACT REPORT
  =============================================================================
  Version Change: N/A (initial) → 1.0.0

  Added Principles:
  - I. Security & Permission Handling
  - II. Pure Swift Implementation
  - III. Memory Safety & Robustness
  - IV. Performance Optimization
  - V. Modular Architecture
  - VI. Comprehensive Testing

  Added Sections:
  - Platform Constraints
  - Development Workflow
  - Governance

  Templates Requiring Updates:
  - .specify/templates/plan-template.md: ✅ No updates required (generic)
  - .specify/templates/spec-template.md: ✅ No updates required (generic)
  - .specify/templates/tasks-template.md: ✅ No updates required (generic)
  - .specify/templates/checklist-template.md: ✅ No updates required (generic)
  - .specify/templates/agent-file-template.md: ✅ No updates required (generic)

  Follow-up TODOs: None
  =============================================================================
-->

# MachScope Constitution

## Core Principles

### I. Security & Permission Handling

All features requiring elevated privileges MUST implement graceful degradation.

- Entitlements (`com.apple.security.cs.debugger`, `get-task-allow`) MUST be requested
  only when strictly necessary and documented in code comments
- When permissions are unavailable, the tool MUST continue operating with reduced
  functionality rather than failing entirely
- Permission errors MUST include actionable guidance directing users to the specific
  System Settings > Privacy & Security path required
- Debugging capabilities MUST be sandboxed appropriately; never assume SIP is disabled
- All file system access MUST use security-scoped bookmarks where applicable

**Rationale**: Binary analysis tools operate in sensitive security contexts. Users may
run MachScope without full permissions, and the tool must remain useful while clearly
communicating what additional capabilities require elevated access.

### II. Pure Swift Implementation

The codebase MUST be implemented in pure Swift without Objective-C bridges unless
absolutely unavoidable.

- Swift 6.2 strict concurrency MUST be enabled and all code MUST compile without
  warnings under `SWIFT_STRICT_CONCURRENCY=complete`
- When Objective-C interop is unavoidable (e.g., certain Darwin APIs), it MUST be
  isolated in dedicated wrapper modules with Swift-native interfaces
- `@objc` attributes MUST NOT appear in public API surfaces
- C interop for system calls (mach, ptrace) is acceptable but MUST be wrapped in
  type-safe Swift abstractions

**Rationale**: Pure Swift ensures type safety, modern concurrency support, and future
compatibility. Minimizing Objective-C reduces bridge overhead and simplifies the
mental model for contributors.

### III. Memory Safety & Robustness

All binary parsing MUST implement bounds checking and handle malformed input gracefully.

- Every buffer read MUST validate offset and size against actual data bounds before
  access; no unchecked pointer arithmetic
- Malformed Mach-O structures (invalid load commands, corrupted headers, truncated
  segments) MUST produce descriptive errors, not crashes
- Error types MUST be exhaustive and domain-specific (e.g., `MachOParseError`,
  `DisassemblyError`) rather than generic
- All throwing functions MUST document their error conditions
- `fatalError()` and force-unwrapping MUST NOT appear in production code paths

**Rationale**: Binary analysis tools process untrusted input by definition. Crashes
or undefined behavior when encountering malformed binaries undermine trust and
prevent analysis of potentially malicious specimens.

### IV. Performance Optimization

Large binary analysis MUST use lazy loading and memory-efficient techniques.

- Binaries over 10MB MUST use `mmap()` for memory-mapped access rather than loading
  entirely into memory
- Parsing MUST be lazy: headers and load commands on open, sections and symbols on
  demand only
- Disassembly MUST support streaming mode for large text segments
- Memory usage MUST remain bounded regardless of input size; target <2x file size
  for fully parsed representation
- Performance-critical paths MUST avoid unnecessary allocations (prefer `Slice`,
  `UnsafeBufferPointer` over copies)

**Rationale**: Production binaries can exceed hundreds of megabytes. Eager loading
would make the tool unusable for real-world analysis tasks.

### V. Modular Architecture

The codebase MUST maintain strict separation between parser, disassembler, and
debugger components.

- Core modules: `MachOKit`, `Disassembler`, `DebuggerCore` MUST have no circular
  dependencies
- All inter-module communication MUST occur through protocols; concrete types MUST
  NOT leak across module boundaries
- CLI MUST be a thin orchestration layer importing core modules; business logic MUST
  NOT reside in CLI code
- Design MUST support future GUI integration without core module changes
- Each module MUST be independently compilable and testable

**Rationale**: Protocol-oriented design enables testing with mocks, supports multiple
frontends (CLI today, GUI later), and allows independent evolution of components.

### VI. Comprehensive Testing

All code MUST be tested with emphasis on correctness over coverage metrics.

- Unit tests MUST cover Mach-O parsing against known reference binaries (both valid
  and intentionally malformed)
- Disassembly tests MUST verify output against known-correct disassembly for ARM64
  instruction patterns
- Integration tests MUST exercise end-to-end workflows (parse → disassemble → output)
- Property-based testing SHOULD be used for edge cases in numeric parsing, bounds
  checking, and instruction decoding
- Tests MUST NOT depend on system binaries that may change between OS versions;
  use committed test fixtures

**Rationale**: Binary analysis correctness is critical—incorrect disassembly or
missed parse errors can lead to flawed security conclusions. Tests against stable
fixtures ensure reproducible verification.

## Platform Constraints

**Target Platform**: arm64-apple-macosx26
**Swift Version**: 6.2.3 minimum
**Dependencies**: No external dependencies unless absolutely necessary

External dependencies MUST meet ALL of the following criteria before adoption:
- Solves a problem that would require >500 lines of equivalent implementation
- Has active maintenance (commits within last 6 months)
- Supports Swift 6 strict concurrency
- Does not introduce transitive dependencies

When external dependencies are unavoidable, they MUST be:
- Documented with justification in the module that imports them
- Isolated behind internal protocols to enable future replacement

## Development Workflow

### Code Review Requirements

All changes MUST be reviewed with attention to:
1. Constitution principle compliance (security, memory safety, modularity)
2. Swift 6 strict concurrency correctness
3. Bounds checking in any parsing code
4. Test coverage for new functionality

### Quality Gates

Before merge, code MUST:
- Compile with zero warnings under strict concurrency
- Pass all existing tests
- Include tests for new functionality
- Document public API with DocC-compatible comments

### Error Handling Standards

- Use `Result` types or throwing functions; never silent failures
- Errors MUST be recoverable where possible
- Error messages MUST include context (file path, offset, expected vs actual)

## Governance

This constitution represents the non-negotiable technical standards for MachScope.

**Amendment Process**:
1. Proposed changes MUST be documented with rationale
2. Breaking changes (principle removal/redefinition) require explicit justification
3. All amendments MUST update version according to semver rules below

**Versioning Policy**:
- MAJOR: Backward-incompatible principle changes or removals
- MINOR: New principles or substantial guidance expansion
- PATCH: Clarifications, wording improvements, non-semantic refinements

**Compliance Review**:
- All PRs MUST verify alignment with applicable principles
- Complexity beyond principles MUST be justified in PR description
- Constitution violations block merge

**Version**: 1.0.0 | **Ratified**: 2026-01-12 | **Last Amended**: 2026-01-12
