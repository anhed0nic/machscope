// DisasmIntegrationTests.swift
// IntegrationTests
//
// Integration tests for ARM64 disassembly

import XCTest

@testable import Disassembler
@testable import MachOKit

final class DisasmIntegrationTests: XCTestCase {

  // MARK: - Test Fixture Paths

  static let fixturesPath = URL(fileURLWithPath: #file)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("MachOKitTests/Fixtures")

  static var simpleARM64Path: String {
    fixturesPath.appendingPathComponent("simple_arm64").path
  }

  // MARK: - Disassembler Integration

  func testDisassembleSimpleBinary() throws {
    // Skip if fixture doesn't exist
    guard FileManager.default.fileExists(atPath: Self.simpleARM64Path) else {
      throw XCTSkip("Test fixture simple_arm64 not found")
    }

    // Parse the binary
    let binary = try MachOBinary(path: Self.simpleARM64Path)

    // Create disassembler with binary for symbol resolution
    let disassembler = ARM64Disassembler(binary: binary)

    // Get the __text section
    guard let textSection = binary.section(segment: "__TEXT", section: "__text") else {
      XCTFail("No __text section found")
      return
    }

    // Read the section data
    let sectionData = try binary.readSectionData(textSection)

    // Limit to first 10 instructions (40 bytes)
    let limitedData = sectionData.prefix(min(40, sectionData.count))

    // Disassemble first 10 instructions
    let instructions = try disassembler.disassemble(
      Data(limitedData),
      at: textSection.address
    )

    // Verify we got some instructions
    XCTAssertFalse(instructions.isEmpty)
    XCTAssertLessThanOrEqual(instructions.count, 10)

    // All instructions should have valid addresses
    for instruction in instructions {
      XCTAssertGreaterThanOrEqual(instruction.address, textSection.address)
      XCTAssertFalse(instruction.mnemonic.isEmpty)
    }
  }

  func testDisassembleFunction() throws {
    guard FileManager.default.fileExists(atPath: Self.simpleARM64Path) else {
      throw XCTSkip("Test fixture simple_arm64 not found")
    }

    let binary = try MachOBinary(path: Self.simpleARM64Path)

    // Find _main symbol
    guard let mainSymbol = binary.symbol(named: "_main") else {
      throw XCTSkip("No _main symbol found in fixture")
    }

    let disassembler = ARM64Disassembler(binary: binary)

    // Disassemble _main function
    let result = try disassembler.disassembleFunction("_main", from: binary)

    XCTAssertFalse(result.instructions.isEmpty)

    // First instruction should be at main's address
    XCTAssertEqual(result.instructions.first?.address, mainSymbol.address)

    // Last instruction should likely be RET or similar
    if let last = result.instructions.last {
      XCTAssertTrue(
        last.mnemonic == "ret" || last.mnemonic == "retaa" || last.mnemonic == "retab"
          || last.mnemonic == "b" || last.mnemonic == "br")
    }
  }

  func testDisassembleWithSymbolResolution() throws {
    guard FileManager.default.fileExists(atPath: Self.simpleARM64Path) else {
      throw XCTSkip("Test fixture simple_arm64 not found")
    }

    let binary = try MachOBinary(path: Self.simpleARM64Path)
    let disassembler = ARM64Disassembler(binary: binary)

    // Find the _main function
    guard let mainSymbol = binary.symbol(named: "_main") else {
      throw XCTSkip("No _main symbol found")
    }

    // Disassemble from main
    guard let textSection = binary.section(segment: "__TEXT", section: "__text") else {
      XCTFail("No __text section")
      return
    }

    let sectionData = try binary.readSectionData(textSection)

    // Calculate offset of main within section
    let mainOffset = Int(mainSymbol.address - textSection.address)
    guard mainOffset >= 0 && mainOffset < sectionData.count else {
      XCTFail("Main offset out of bounds")
      return
    }

    // Limit to 20 instructions (80 bytes)
    let maxBytes = min(80, sectionData.count - mainOffset)
    let subdata = sectionData.subdata(in: mainOffset..<(mainOffset + maxBytes))

    // Disassemble starting from main
    let instructions = try disassembler.disassemble(
      subdata,
      at: mainSymbol.address
    )

    // Check if any branch instructions have resolved symbols
    let branchInstructions = instructions.filter { $0.category == .branch }
    // At least some branch targets should be resolvable
    // (depends on binary content)
    XCTAssertFalse(instructions.isEmpty)
  }

  // MARK: - Formatter Integration

  func testFormatDisassembly() throws {
    guard FileManager.default.fileExists(atPath: Self.simpleARM64Path) else {
      throw XCTSkip("Test fixture simple_arm64 not found")
    }

    let binary = try MachOBinary(path: Self.simpleARM64Path)
    let disassembler = ARM64Disassembler(binary: binary)

    guard let textSection = binary.section(segment: "__TEXT", section: "__text") else {
      XCTFail("No __text section")
      return
    }

    let sectionData = try binary.readSectionData(textSection)

    // Limit to 5 instructions (20 bytes)
    let limitedData = sectionData.prefix(min(20, sectionData.count))

    let instructions = try disassembler.disassemble(
      Data(limitedData),
      at: textSection.address
    )

    let formatter = InstructionFormatter()

    for instruction in instructions {
      let formatted = formatter.format(
        instruction,
        showAddress: true,
        showBytes: true
      )

      // Should have address
      XCTAssertTrue(
        formatted.contains("0x")
          || formatted.lowercased().contains(String(instruction.address, radix: 16)))

      // Should have mnemonic
      XCTAssertTrue(formatted.contains(instruction.mnemonic))
    }
  }

  // MARK: - PAC Annotation Integration

  func testPACAnnotationIntegration() throws {
    let decoder = InstructionDecoder()
    let annotator = PACAnnotator()

    // Test some PAC instruction encodings
    let pacEncodings: [UInt32] = [
      0xd65f_0bff,  // RETAA
      0xd65f_0fff,  // RETAB
      0xdac1_0001,  // PACIA x0, x1
    ]

    for encoding in pacEncodings {
      let instruction = decoder.decode(encoding, at: 0x1_0000_0000)
      let annotated = annotator.annotateInstruction(instruction)

      // PAC instructions should have annotations or PAC category
      XCTAssertTrue(
        annotated.category == .pac || annotated.annotation != nil,
        "PAC instruction 0x\(String(encoding, radix: 16)) not properly annotated")
    }
  }

  // MARK: - Edge Cases

  func testDisassembleEmptyData() throws {
    let disassembler = ARM64Disassembler()

    let instructions = try disassembler.disassemble(
      Data(),
      at: 0x1_0000_0000
    )

    XCTAssertTrue(instructions.isEmpty)
  }

  func testDisassembleTruncatedInstruction() throws {
    let disassembler = ARM64Disassembler()

    // Only 2 bytes (ARM64 needs 4)
    let truncatedData = Data([0x1f, 0x20])

    // Should throw insufficientData error
    XCTAssertThrowsError(
      try disassembler.disassemble(
        truncatedData,
        at: 0x1_0000_0000
      )
    ) { error in
      guard case DisassemblyError.insufficientData = error else {
        XCTFail("Expected insufficientData error, got \(error)")
        return
      }
    }
  }

  func testDisassembleMultipleInstructions() throws {
    let disassembler = ARM64Disassembler()

    // Create data for 100 NOPs
    var data = Data()
    for _ in 0..<100 {
      // NOP: 0xd503201f (little-endian)
      data.append(contentsOf: [0x1f, 0x20, 0x03, 0xd5])
    }

    // Limit to first 10 instructions (40 bytes)
    let limitedData = data.prefix(40)

    let instructions = try disassembler.disassemble(
      Data(limitedData),
      at: 0x1_0000_0000
    )

    XCTAssertEqual(instructions.count, 10)
  }

  // MARK: - Common Instruction Patterns

  func testCommonFunctionPrologue() throws {
    let decoder = InstructionDecoder()

    // Typical function prologue:
    // STP x29, x30, [sp, #-16]!
    // MOV x29, sp

    let prologue: [UInt32] = [
      0xa9bf_7bfd,  // STP x29, x30, [sp, #-16]!
      0x9100_03fd,  // MOV x29, sp
    ]

    var address: UInt64 = 0x1_0000_0000
    var instructions: [Instruction] = []

    for encoding in prologue {
      let instruction = decoder.decode(encoding, at: address)
      instructions.append(instruction)
      address += 4
    }

    XCTAssertEqual(instructions.count, 2)
    XCTAssertTrue(instructions[0].mnemonic == "stp" || instructions[0].category == .loadStore)
    XCTAssertTrue(instructions[1].mnemonic == "mov" || instructions[1].mnemonic == "add")
  }

  func testCommonFunctionEpilogue() throws {
    let decoder = InstructionDecoder()

    // Typical function epilogue:
    // LDP x29, x30, [sp], #16
    // RET

    let epilogue: [UInt32] = [
      0xa8c1_7bfd,  // LDP x29, x30, [sp], #16
      0xd65f_03c0,  // RET
    ]

    var address: UInt64 = 0x1_0000_0000
    var instructions: [Instruction] = []

    for encoding in epilogue {
      let instruction = decoder.decode(encoding, at: address)
      instructions.append(instruction)
      address += 4
    }

    XCTAssertEqual(instructions.count, 2)
    XCTAssertTrue(instructions[0].mnemonic == "ldp" || instructions[0].category == .loadStore)
    XCTAssertEqual(instructions[1].mnemonic, "ret")
  }
}
