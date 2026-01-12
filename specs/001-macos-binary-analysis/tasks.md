# Tasks: MachScope Binary Analysis Tool

**Input**: Design documents from `/specs/001-macos-binary-analysis/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/cli-interface.md

**Tests**: Test tasks are included as this is a binary analysis tool where correctness is critical.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and Swift Package structure per plan.md

- [X] T001 Create Package.swift with four targets (MachOKit, Disassembler, DebuggerCore, MachScope) per plan.md
- [X] T002 [P] Create directory structure: Sources/MachOKit/, Sources/Disassembler/, Sources/DebuggerCore/, Sources/MachScope/
- [X] T003 [P] Create test directory structure: Tests/MachOKitTests/, Tests/DisassemblerTests/, Tests/DebuggerCoreTests/, Tests/IntegrationTests/
- [X] T004 [P] Create Resources/MachScope.entitlements with com.apple.security.cs.debugger and get-task-allow
- [X] T005 [P] Create Tests/MachOKitTests/Fixtures/ directory with placeholder README
- [X] T006 Update CLAUDE.md Implementation Status: Phase 1 Setup = Complete

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**CRITICAL**: No user story work can begin until this phase is complete

- [X] T007 Implement BinaryReader struct with bounds-checked read methods in Sources/MachOKit/IO/BinaryReader.swift
- [X] T008 [P] Implement MemoryMappedFile class with mmap wrapper in Sources/MachOKit/IO/MemoryMappedFile.swift
- [X] T009 Implement MachOParseError enum with all error cases and context in Sources/MachOKit/Errors/MachOParseError.swift
- [X] T010 [P] Implement CPUType and CPUSubtype enums in Sources/MachOKit/Header/CPUType.swift
- [X] T011 [P] Implement FileType and MachHeaderFlags enums in Sources/MachOKit/Header/MachHeader.swift
- [X] T012 [P] Create placeholder main.swift in Sources/MachScope/main.swift
- [X] T013 Create test fixture: compile simple ARM64 binary to Tests/MachOKitTests/Fixtures/simple_arm64
- [X] T014 [P] Create test fixture: compile Fat/Universal binary to Tests/MachOKitTests/Fixtures/fat_binary
- [X] T015 [P] Create test fixture: truncated binary to Tests/MachOKitTests/Fixtures/malformed/truncated
- [X] T016 Verify swift build succeeds with basic structure
- [X] T017 Update CLAUDE.md Implementation Status: Phase 2 Foundational = Complete

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Parse Mach-O Binary Structure (Priority: P1) MVP

**Goal**: Security researcher can parse any macOS executable to see headers, load commands, segments, sections, and symbols.

**Independent Test**: Parse `/bin/ls` and verify output matches expected structure (header magic, CPU type, segments).

### Tests for User Story 1

- [ ] T018 [P] [US1] Unit test for MachHeader parsing in Tests/MachOKitTests/HeaderTests.swift
- [ ] T019 [P] [US1] Unit test for LoadCommand parsing in Tests/MachOKitTests/LoadCommandTests.swift
- [ ] T020 [P] [US1] Unit test for Segment/Section parsing in Tests/MachOKitTests/SegmentTests.swift
- [ ] T021 [P] [US1] Unit test for Fat binary detection and slice extraction in Tests/MachOKitTests/FatBinaryTests.swift
- [ ] T022 [P] [US1] Unit test for Symbol table parsing in Tests/MachOKitTests/SymbolTests.swift
- [ ] T023 [P] [US1] Unit test for malformed binary handling in Tests/MachOKitTests/ErrorHandlingTests.swift
- [ ] T024 [US1] Integration test: parse simple_arm64 and fat_binary fixtures in Tests/IntegrationTests/ParseIntegrationTests.swift

### Implementation for User Story 1

#### Core Parsing

- [ ] T025 [US1] Implement MachHeader struct and parsing in Sources/MachOKit/Header/MachHeader.swift
- [ ] T026 [US1] Implement FatHeader and FatArch parsing in Sources/MachOKit/Header/FatHeader.swift
- [ ] T027 [US1] Implement LoadCommand base and LoadCommandType enum in Sources/MachOKit/LoadCommands/LoadCommand.swift
- [ ] T028 [P] [US1] Implement SegmentCommand (LC_SEGMENT_64) parsing in Sources/MachOKit/LoadCommands/SegmentCommand.swift
- [ ] T029 [P] [US1] Implement SymtabCommand (LC_SYMTAB) parsing in Sources/MachOKit/LoadCommands/SymtabCommand.swift
- [ ] T030 [P] [US1] Implement DyldCommand (LC_LOAD_DYLIB, etc.) parsing in Sources/MachOKit/LoadCommands/DyldCommand.swift
- [ ] T031 [US1] Implement Segment struct in Sources/MachOKit/Sections/Segment.swift
- [ ] T032 [US1] Implement Section struct and SectionType enum in Sources/MachOKit/Sections/Section.swift
- [ ] T033 [US1] Implement Symbol struct and SymbolType enum in Sources/MachOKit/Symbols/Symbol.swift
- [ ] T034 [US1] Implement SymbolTable lazy loading in Sources/MachOKit/Symbols/SymbolTable.swift
- [ ] T035 [US1] Implement StringTable for symbol names in Sources/MachOKit/Symbols/StringTable.swift
- [ ] T036 [US1] Implement MachOBinary main entry point in Sources/MachOKit/MachOBinary.swift

#### CLI Parse Command

- [ ] T037 [US1] Implement ArgumentParser for CLI in Sources/MachScope/Utilities/ArgumentParser.swift
- [ ] T038 [US1] Implement TextFormatter for human-readable output in Sources/MachScope/Output/TextFormatter.swift
- [ ] T039 [US1] Implement JSONFormatter for --json output in Sources/MachScope/Output/JSONFormatter.swift
- [ ] T040 [US1] Implement ParseCommand with all options in Sources/MachScope/Commands/ParseCommand.swift
- [ ] T041 [US1] Wire ParseCommand to main.swift entry point in Sources/MachScope/main.swift
- [ ] T042 Update CLAUDE.md Implementation Status: Phase 3 US1 Parse Mach-O = Complete

**Checkpoint**: At this point, `machscope parse /bin/ls` should work with header, segments, sections, and symbols output.

---

## Phase 4: User Story 2 - Disassemble ARM64 Code (Priority: P2)

**Goal**: Reverse engineer can examine assembly code of functions with symbols resolved and PAC instructions highlighted.

**Independent Test**: Disassemble a known function and verify instruction mnemonics match expected output.

### Tests for User Story 2

- [ ] T043 [P] [US2] Unit test for instruction decoding in Tests/DisassemblerTests/DecoderTests.swift
- [ ] T044 [P] [US2] Unit test for instruction formatting in Tests/DisassemblerTests/FormatterTests.swift
- [ ] T045 [P] [US2] Unit test for PAC instruction annotation in Tests/DisassemblerTests/PACAnnotatorTests.swift
- [ ] T046 [P] [US2] Unit test for unknown/invalid instruction graceful handling in Tests/DisassemblerTests/UnknownInstructionTests.swift
- [ ] T047 [US2] Integration test: disassemble simple_arm64 fixture in Tests/IntegrationTests/DisasmIntegrationTests.swift

### Implementation for User Story 2

#### Instruction Decoding

- [ ] T048 [US2] Implement Instruction model and InstructionCategory enum in Sources/Disassembler/Instruction.swift
- [ ] T049 [US2] Implement DisassemblyError enum in Sources/Disassembler/Errors/DisassemblyError.swift
- [ ] T050 [US2] Implement InstructionDecoder base with bit extraction utilities in Sources/Disassembler/Decoder/InstructionDecoder.swift
- [ ] T051 [P] [US2] Implement data processing decoder (ADD, SUB, MOV, etc.) in Sources/Disassembler/Decoder/DataProcessing.swift
- [ ] T052 [P] [US2] Implement branch decoder (B, BL, BR, RET) in Sources/Disassembler/Decoder/Branch.swift
- [ ] T053 [P] [US2] Implement load/store decoder (LDR, STR, LDP, STP) in Sources/Disassembler/Decoder/LoadStore.swift
- [ ] T054 [P] [US2] Implement system instruction decoder (SVC, NOP, PAC) in Sources/Disassembler/Decoder/System.swift

#### Formatting and Analysis

- [ ] T055 [US2] Implement InstructionFormatter for assembly notation in Sources/Disassembler/Formatter/InstructionFormatter.swift
- [ ] T056 [US2] Implement OperandFormatter for operand display in Sources/Disassembler/Formatter/OperandFormatter.swift
- [ ] T057 [US2] Implement SymbolResolver protocol and implementation in Sources/Disassembler/Analysis/SymbolResolver.swift
- [ ] T058 [US2] Implement PACAnnotator for PAC instruction highlighting in Sources/Disassembler/Analysis/PACAnnotator.swift
- [ ] T059 [US2] Implement SwiftDemangler for Swift symbol names in Sources/Disassembler/Analysis/SwiftDemangler.swift
- [ ] T060 [US2] Implement ARM64Disassembler main entry point in Sources/Disassembler/ARM64Disassembler.swift

#### CLI Disasm Command

- [ ] T061 [US2] Implement DisasmCommand with all options in Sources/MachScope/Commands/DisasmCommand.swift
- [ ] T062 [US2] Wire DisasmCommand to main.swift and update help in Sources/MachScope/main.swift
- [ ] T063 Update CLAUDE.md Implementation Status: Phase 4 US2 Disassemble = Complete

**Checkpoint**: At this point, `machscope disasm /bin/ls --function _main` should work with annotated output.

---

## Phase 5: User Story 3 - Check System Permissions (Priority: P3)

**Goal**: User can verify permissions for all features with actionable guidance for missing permissions.

**Independent Test**: Run check-permissions on clean system and verify accurate detection of permission states.

### Tests for User Story 3

- [X] T064 [P] [US3] Unit test for permission detection in Tests/DebuggerCoreTests/PermissionTests.swift
- [X] T065 [P] [US3] Unit test for SIP detection in Tests/DebuggerCoreTests/SIPDetectorTests.swift

### Implementation for User Story 3

- [X] T066 [US3] Implement DebuggerError enum in Sources/DebuggerCore/Errors/DebuggerError.swift
- [X] T067 [US3] Implement SIPDetector for System Integrity Protection status in Sources/DebuggerCore/Permissions/SIPDetector.swift
- [X] T068 [US3] Implement EntitlementValidator for debugger entitlement check in Sources/DebuggerCore/Permissions/EntitlementValidator.swift
- [X] T069 [US3] Implement PermissionChecker with tiered capability detection in Sources/DebuggerCore/Permissions/PermissionChecker.swift
- [X] T070 [US3] Implement CheckPermissionsCommand with guidance output in Sources/MachScope/Commands/CheckPermissionsCommand.swift
- [X] T071 [US3] Wire CheckPermissionsCommand to main.swift in Sources/MachScope/main.swift
- [X] T072 Update CLAUDE.md Implementation Status: Phase 5 US3 Permissions = Complete

**Checkpoint**: At this point, `machscope check-permissions` should display permission status with actionable guidance.

---

## Phase 6: User Story 4 - Debug Running Process (Priority: P4)

**Goal**: Advanced user can attach to processes, set breakpoints, step through execution, and inspect state.

**Independent Test**: Attach to test program, set breakpoint, hit it, read registers.

**Dependencies**: Requires User Story 3 (permission checking) to be complete for error handling.

### Tests for User Story 4

- [ ] T073 [P] [US4] Unit test for breakpoint management in Tests/DebuggerCoreTests/BreakpointTests.swift
- [ ] T074 [P] [US4] Unit test for register reading in Tests/DebuggerCoreTests/RegisterTests.swift
- [ ] T075 [US4] Integration test: attach/breakpoint/continue cycle in Tests/IntegrationTests/DebuggerIntegrationTests.swift

### Implementation for User Story 4

#### Process Attachment

- [ ] T076 [US4] Implement TaskPort wrapper for task_for_pid in Sources/DebuggerCore/Process/TaskPort.swift
- [ ] T077 [US4] Implement ProcessAttachment for process attach/detach in Sources/DebuggerCore/Process/ProcessAttachment.swift
- [ ] T078 [US4] Implement ThreadState for thread management in Sources/DebuggerCore/Process/ThreadState.swift

#### Memory and Registers

- [ ] T079 [P] [US4] Implement MemoryReader for vm_read in Sources/DebuggerCore/Memory/MemoryReader.swift
- [ ] T080 [P] [US4] Implement MemoryWriter for vm_write in Sources/DebuggerCore/Memory/MemoryWriter.swift
- [ ] T081 [US4] Implement ARM64Registers struct for register state in Sources/DebuggerCore/Process/ARM64Registers.swift

#### Breakpoints

- [ ] T082 [US4] Implement Breakpoint model in Sources/DebuggerCore/Breakpoints/Breakpoint.swift
- [ ] T083 [US4] Implement BreakpointManager for set/remove/hit in Sources/DebuggerCore/Breakpoints/BreakpointManager.swift

#### Exception Handling

- [ ] T084 [US4] Implement ExceptionHandler for Mach exceptions in Sources/DebuggerCore/Exceptions/ExceptionHandler.swift
- [ ] T085 [US4] Implement MachExceptionServer for exception port in Sources/DebuggerCore/Exceptions/MachExceptionServer.swift

#### Debugger Entry Point

- [ ] T086 [US4] Implement Debugger main class with all operations in Sources/DebuggerCore/Debugger.swift

#### CLI Debug Command

- [ ] T087 [US4] Implement DebugCommand with interactive mode in Sources/MachScope/Commands/DebugCommand.swift
- [ ] T088 [US4] Wire DebugCommand to main.swift in Sources/MachScope/main.swift
- [ ] T089 Update CLAUDE.md Implementation Status: Phase 6 US4 Debug = Complete

**Checkpoint**: At this point, `machscope debug <pid>` should allow interactive debugging with breakpoints and stepping.

---

## Phase 7: User Story 5 - Export Symbol and String Data (Priority: P5)

**Goal**: Malware analyst can extract symbols and strings in JSON format for automated processing.

**Independent Test**: Export symbols/strings from binary and validate JSON structure.

**Dependencies**: Uses parsing from User Story 1.

### Tests for User Story 5

- [X] T090 [P] [US5] Unit test for string extraction in Tests/MachOKitTests/StringExtractionTests.swift
- [X] T091 [US5] Integration test: export simple_arm64 fixture symbols as JSON in Tests/IntegrationTests/ExportIntegrationTests.swift

### Implementation for User Story 5

- [X] T092 [US5] Implement string extraction from __cstring and other sections in Sources/MachOKit/Symbols/StringExtractor.swift
- [X] T093 [US5] Add --strings flag handling to ParseCommand in Sources/MachScope/Commands/ParseCommand.swift
- [X] T094 [US5] Enhance JSONFormatter for complete symbol/string export in Sources/MachScope/Output/JSONFormatter.swift
- [X] T095 Update CLAUDE.md Implementation Status: Phase 7 US5 Export = Complete

**Checkpoint**: At this point, `machscope parse /bin/ls --symbols --strings --json` should output complete data.

---

## Phase 8: Code Signature Parsing (Extended Parsing)

**Goal**: Parse code signature data including entitlements and CDHash for security analysis.

**Note**: This extends User Story 1 with code signature capabilities mentioned in FR-005.

### Tests for Code Signature

- [X] T096 [P] [US1] Unit test for SuperBlob parsing in Tests/MachOKitTests/CodeSignatureTests.swift
- [X] T097 [US1] Unit test for entitlement extraction in Tests/MachOKitTests/EntitlementTests.swift

### Implementation for Code Signature

- [X] T098 [US1] Implement CodeSignatureCommand (LC_CODE_SIGNATURE) parsing in Sources/MachOKit/LoadCommands/CodeSignatureCommand.swift
- [X] T099 [US1] Implement SuperBlob parser in Sources/MachOKit/CodeSignature/SuperBlob.swift
- [X] T100 [US1] Implement CodeDirectory parser in Sources/MachOKit/CodeSignature/CodeDirectory.swift
- [X] T101 [US1] Implement Entitlements parser (XML and DER) in Sources/MachOKit/CodeSignature/Entitlements.swift
- [X] T102 [US1] Add --signatures and --entitlements flags to ParseCommand in Sources/MachScope/Commands/ParseCommand.swift
- [X] T103 Update CLAUDE.md Implementation Status: Phase 8 Code Signature = Complete

**Checkpoint**: `machscope parse /bin/ls --signatures --entitlements` shows code signature details.

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Final quality improvements and documentation

- [X] T104 [P] Add --version flag implementation in Sources/MachScope/main.swift
- [X] T105 [P] Add --color option (auto/always/never) support in Sources/MachScope/Output/TextFormatter.swift
- [X] T106 Implement consistent exit codes per cli-interface.md in Sources/MachScope/main.swift
- [X] T107 [P] Add progress indication for large binary parsing in Sources/MachOKit/MachOBinary.swift
- [X] T108 [P] Run swift-format on all source files
- [X] T109 Run full test suite and fix any failures
- [X] T110 Validate all quickstart.md examples work correctly
- [X] T111 End-to-end test: parse, disasm, and debug workflow in Tests/IntegrationTests/IntegrationTests.swift
- [X] T112 Update CLAUDE.md Implementation Status: Phase 9 Polish = Complete, all phases done

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational - Core parsing capability
- **User Story 2 (Phase 4)**: Depends on Foundational + MachOKit protocol for SymbolResolving
- **User Story 3 (Phase 5)**: Depends on Foundational only
- **User Story 4 (Phase 6)**: Depends on User Story 3 (permission checking)
- **User Story 5 (Phase 7)**: Depends on User Story 1 (parsing infrastructure)
- **Code Signature (Phase 8)**: Depends on User Story 1 (extends parsing)
- **Polish (Phase 9)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational - Uses MachOKit for binary context but independently testable
- **User Story 3 (P3)**: Can start after Foundational - Completely independent
- **User Story 4 (P4)**: Depends on User Story 3 for permission handling - Must complete US3 first
- **User Story 5 (P5)**: Extends User Story 1 - Must complete US1 first

### Parallel Opportunities Within Stories

**User Story 1**: T018-T023 (tests), T028-T030 (load commands) can run in parallel
**User Story 2**: T043-T046 (tests), T051-T054 (decoders) can run in parallel
**User Story 3**: T064-T065 (tests) can run in parallel
**User Story 4**: T073-T074 (tests), T079-T080 (memory) can run in parallel
**User Story 5**: Mostly sequential, small scope

---

## Parallel Example: User Story 1

```bash
# Launch all tests for User Story 1 together:
Task: "Unit test for MachHeader parsing in Tests/MachOKitTests/HeaderTests.swift"
Task: "Unit test for LoadCommand parsing in Tests/MachOKitTests/LoadCommandTests.swift"
Task: "Unit test for Segment/Section parsing in Tests/MachOKitTests/SegmentTests.swift"
Task: "Unit test for Fat binary detection in Tests/MachOKitTests/FatBinaryTests.swift"
Task: "Unit test for Symbol table parsing in Tests/MachOKitTests/SymbolTests.swift"
Task: "Unit test for malformed binary handling in Tests/MachOKitTests/ErrorHandlingTests.swift"

# After tests exist, launch parallel load command implementations:
Task: "Implement SegmentCommand (LC_SEGMENT_64) parsing in Sources/MachOKit/LoadCommands/SegmentCommand.swift"
Task: "Implement SymtabCommand (LC_SYMTAB) parsing in Sources/MachOKit/LoadCommands/SymtabCommand.swift"
Task: "Implement DyldCommand (LC_LOAD_DYLIB, etc.) parsing in Sources/MachOKit/LoadCommands/DyldCommand.swift"
```

---

## Parallel Example: User Story 2

```bash
# Launch all tests for User Story 2 together:
Task: "Unit test for instruction decoding in Tests/DisassemblerTests/DecoderTests.swift"
Task: "Unit test for instruction formatting in Tests/DisassemblerTests/FormatterTests.swift"
Task: "Unit test for PAC instruction annotation in Tests/DisassemblerTests/PACAnnotatorTests.swift"
Task: "Unit test for unknown/invalid instruction graceful handling in Tests/DisassemblerTests/UnknownInstructionTests.swift"

# Launch all decoder implementations in parallel:
Task: "Implement data processing decoder (ADD, SUB, MOV, etc.) in Sources/Disassembler/Decoder/DataProcessing.swift"
Task: "Implement branch decoder (B, BL, BR, RET) in Sources/Disassembler/Decoder/Branch.swift"
Task: "Implement load/store decoder (LDR, STR, LDP, STP) in Sources/Disassembler/Decoder/LoadStore.swift"
Task: "Implement system instruction decoder (SVC, NOP, PAC) in Sources/Disassembler/Decoder/System.swift"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T006)
2. Complete Phase 2: Foundational (T007-T017)
3. Complete Phase 3: User Story 1 (T018-T042)
4. **STOP and VALIDATE**: Test `machscope parse simple_arm64` independently
5. Deploy/demo binary parsing capability

### Incremental Delivery

1. Complete Setup + Foundational -> Foundation ready
2. Add User Story 1 -> Test independently -> **MVP: Binary Parser**
3. Add User Story 2 -> Test independently -> **Adds: Disassembler**
4. Add User Story 3 -> Test independently -> **Adds: Permission Checking**
5. Add User Story 4 -> Test independently -> **Adds: Debugger** (requires US3)
6. Add User Story 5 -> Test independently -> **Adds: Data Export** (requires US1)
7. Add Code Signature -> Test independently -> **Extends: Parsing**
8. Polish phase -> Final validation

### Single Developer Strategy

Execute phases sequentially in priority order:
1. Setup + Foundational
2. User Story 1 (P1) - MVP
3. User Story 2 (P2)
4. User Story 3 (P3)
5. User Story 4 (P4)
6. User Story 5 (P5)
7. Code Signature + Polish

---

## Summary

| Phase | User Story | Tasks | Parallel Tasks |
|-------|------------|-------|----------------|
| 1 | Setup | 6 | 4 |
| 2 | Foundational | 11 | 6 |
| 3 | US1 - Parse Mach-O | 25 | 9 |
| 4 | US2 - Disassemble | 21 | 9 |
| 5 | US3 - Permissions | 9 | 2 |
| 6 | US4 - Debug | 17 | 4 |
| 7 | US5 - Export | 6 | 1 |
| 8 | Code Signature | 8 | 1 |
| 9 | Polish | 9 | 4 |
| **Total** | | **112** | **40** |

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Verify tests fail before implementing
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Test binaries should be committed to the repository for reproducible testing
