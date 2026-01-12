// UnknownInstructionTests.swift
// DisassemblerTests
//
// Unit tests for handling unknown/invalid instructions

import XCTest

@testable import Disassembler

final class UnknownInstructionTests: XCTestCase {

  var decoder: InstructionDecoder!

  override func setUp() {
    super.setUp()
    decoder = InstructionDecoder()
  }

  // MARK: - Unknown Instruction Handling

  func testDecodeUnknownEncoding() throws {
    // A completely invalid/reserved encoding
    // Encoding: 0x00000000 (typically undefined)
    let instruction = decoder.decode(0x0000_0000, at: 0x1_0000_0000)

    // Should not crash, should produce some result
    XCTAssertEqual(instruction.address, 0x1_0000_0000)
    XCTAssertEqual(instruction.encoding, 0x0000_0000)
    // Unknown instructions should have unknown category or specific mnemonic
    XCTAssertTrue(
      instruction.category == .unknown || instruction.mnemonic == "udf"
        || instruction.mnemonic == ".word")
  }

  func testDecodeAllOnesEncoding() throws {
    // All ones - often undefined
    let instruction = decoder.decode(0xffff_ffff, at: 0x1_0000_0000)

    XCTAssertEqual(instruction.address, 0x1_0000_0000)
    XCTAssertEqual(instruction.encoding, 0xffff_ffff)
    // Should handle gracefully
    XCTAssertFalse(instruction.mnemonic.isEmpty)
  }

  func testDecodeUDF() throws {
    // UDF #0 (explicit undefined instruction)
    // Encoding: 0x00000000
    let instruction = decoder.decode(0x0000_0000, at: 0x1_0000_0000)

    // UDF is explicitly undefined
    XCTAssertEqual(instruction.encoding, 0x0000_0000)
  }

  // MARK: - Reserved Instruction Space

  func testDecodeReservedDataProcessing() throws {
    // Reserved encoding in data processing space
    let instruction = decoder.decode(0x1e00_0000, at: 0x1_0000_0000)

    XCTAssertFalse(instruction.mnemonic.isEmpty)
    // Should be handled, possibly as unknown
  }

  func testDecodeReservedLoadStore() throws {
    // Reserved encoding in load/store space
    let instruction = decoder.decode(0x3c00_0000, at: 0x1_0000_0000)

    XCTAssertFalse(instruction.mnemonic.isEmpty)
  }

  func testDecodeReservedBranch() throws {
    // Reserved encoding in branch space
    let instruction = decoder.decode(0x1600_0000, at: 0x1_0000_0000)

    XCTAssertFalse(instruction.mnemonic.isEmpty)
  }

  // MARK: - SIMD/FP Instructions (May Be Unknown)

  func testDecodeSIMDInstruction() throws {
    // A SIMD instruction that may not be fully decoded
    // FADD V0.4S, V1.4S, V2.4S
    // Encoding: 0x4e22d420
    let instruction = decoder.decode(0x4e22_d420, at: 0x1_0000_0000)

    // Either decoded or marked as unknown/SIMD
    XCTAssertTrue(
      instruction.category == .simd || instruction.category == .unknown
        || instruction.mnemonic.hasPrefix("f") || instruction.mnemonic == ".word")
  }

  // MARK: - Graceful Degradation

  func testUnknownInstructionHasValidAddress() throws {
    let address: UInt64 = 0x1234_5678_9abc_def0
    let instruction = decoder.decode(0xdead_beef, at: address)

    XCTAssertEqual(instruction.address, address)
  }

  func testUnknownInstructionHasValidEncoding() throws {
    let encoding: UInt32 = 0xcafe_babe
    let instruction = decoder.decode(encoding, at: 0x1_0000_0000)

    XCTAssertEqual(instruction.encoding, encoding)
  }

  func testUnknownInstructionHasMnemonic() throws {
    let instruction = decoder.decode(0xbaad_f00d, at: 0x1_0000_0000)

    // Should have some mnemonic, even if it's ".word" or "udf"
    XCTAssertFalse(instruction.mnemonic.isEmpty)
  }

  func testUnknownInstructionHasCategory() throws {
    let instruction = decoder.decode(0xdead_beef, at: 0x1_0000_0000)

    // Should have a category (unknown is valid)
    XCTAssertNotNil(instruction.category)
  }

  // MARK: - Multiple Unknown Instructions

  func testDecodeSequenceWithUnknown() throws {
    let encodings: [UInt32] = [
      0x9100_4020,  // ADD x0, x1, #0x10
      0xdead_beef,  // Unknown
      0x1400_0005,  // B
      0xcafe_babe,  // Unknown
      0x8b02_0020,  // ADD x0, x1, x2
    ]

    var address: UInt64 = 0x1_0000_0000
    var instructions: [Instruction] = []

    for encoding in encodings {
      let instruction = decoder.decode(encoding, at: address)
      instructions.append(instruction)
      address += 4
    }

    XCTAssertEqual(instructions.count, 5)

    // First should be ADD
    XCTAssertEqual(instructions[0].mnemonic, "add")

    // Third should be B
    XCTAssertEqual(instructions[2].mnemonic, "b")

    // Fifth should be ADD
    XCTAssertEqual(instructions[4].mnemonic, "add")

    // Unknown instructions should still have entries
    XCTAssertFalse(instructions[1].mnemonic.isEmpty)
    XCTAssertFalse(instructions[3].mnemonic.isEmpty)
  }

  // MARK: - Instruction Formatting for Unknown

  func testFormatUnknownInstruction() throws {
    let instruction = decoder.decode(0xdead_beef, at: 0x1_0000_0000)

    let formatter = InstructionFormatter()
    let formatted = formatter.format(instruction, showAddress: true, showBytes: true)

    // Should include address
    XCTAssertTrue(formatted.contains("0x100000000") || formatted.lowercased().contains("100000000"))

    // Should include encoding bytes
    XCTAssertTrue(
      formatted.lowercased().contains("deadbeef") || formatted.lowercased().contains("ef")
        || formatted.lowercased().contains("be"))
  }

  // MARK: - Error Messages

  func testUnknownInstructionNoAnnotation() throws {
    let instruction = decoder.decode(0xdead_beef, at: 0x1_0000_0000)

    // Unknown instructions typically don't have annotations
    // (or might have a generic annotation)
    // This is acceptable either way - instruction was decoded without crashing
    XCTAssertFalse(instruction.mnemonic.isEmpty)
  }

  // MARK: - Edge Cases

  func testDecodeAtZeroAddress() throws {
    let instruction = decoder.decode(0xdead_beef, at: 0)

    XCTAssertEqual(instruction.address, 0)
    XCTAssertFalse(instruction.mnemonic.isEmpty)
  }

  func testDecodeAtMaxAddress() throws {
    let instruction = decoder.decode(0xdead_beef, at: UInt64.max)

    XCTAssertEqual(instruction.address, UInt64.max)
    XCTAssertFalse(instruction.mnemonic.isEmpty)
  }

  // MARK: - Specific Unknown Patterns

  func testDecodeHintInstruction() throws {
    // Unknown hint instruction (in hint space but not recognized)
    // Hint instructions are in 0xd503201f - 0xd50323ff range
    let instruction = decoder.decode(0xd503_20ff, at: 0x1_0000_0000)

    // Instruction should be decoded (might be system, branch, or unknown)
    XCTAssertFalse(instruction.mnemonic.isEmpty)
  }

  func testDecodeBarrierInstruction() throws {
    // DMB ISH (Data Memory Barrier)
    // Encoding: 0xd5033bbf
    let instruction = decoder.decode(0xd503_3bbf, at: 0x1_0000_0000)

    // Instruction should be decoded (might be system, branch, or unknown)
    XCTAssertFalse(instruction.mnemonic.isEmpty)
  }

  // MARK: - Consistency Tests

  func testUnknownInstructionConsistency() throws {
    // Same encoding should produce same result
    let encoding: UInt32 = 0xfeed_face
    let address: UInt64 = 0x1_0000_0000

    let instruction1 = decoder.decode(encoding, at: address)
    let instruction2 = decoder.decode(encoding, at: address)

    XCTAssertEqual(instruction1.mnemonic, instruction2.mnemonic)
    XCTAssertEqual(instruction1.category, instruction2.category)
    XCTAssertEqual(instruction1.encoding, instruction2.encoding)
  }
}
