// DecoderTests.swift
// DisassemblerTests
//
// Unit tests for ARM64 instruction decoding

import XCTest

@testable import Disassembler

final class DecoderTests: XCTestCase {

  // MARK: - Branch Instructions

  func testDecodeBUnconditional() throws {
    // B #0x14 (branch forward 5 instructions = 20 bytes)
    // Encoding: 0x14000005
    let decoder = InstructionDecoder()
    let instruction = decoder.decode(0x1400_0005, at: 0x1_0000_0000)

    XCTAssertEqual(instruction.mnemonic, "b")
    XCTAssertEqual(instruction.category, .branch)
    XCTAssertEqual(instruction.targetAddress, 0x1_0000_0014)
  }

  func testDecodeBL() throws {
    // BL #0x1000 (branch and link)
    // Encoding: 0x94000400
    let decoder = InstructionDecoder()
    let instruction = decoder.decode(0x9400_0400, at: 0x1_0000_0000)

    XCTAssertEqual(instruction.mnemonic, "bl")
    XCTAssertEqual(instruction.category, .branch)
    XCTAssertEqual(instruction.targetAddress, 0x1_0000_1000)
  }

  func testDecodeBConditional() throws {
    // B.EQ #0x10 (branch if equal)
    // Encoding: 0x54000080
    let decoder = InstructionDecoder()
    let instruction = decoder.decode(0x5400_0080, at: 0x1_0000_0000)

    XCTAssertEqual(instruction.mnemonic, "b.eq")
    XCTAssertEqual(instruction.category, .branch)
    XCTAssertEqual(instruction.targetAddress, 0x1_0000_0010)
  }

  func testDecodeBR() throws {
    // BR x16
    // Encoding: 0xd61f0200
    let decoder = InstructionDecoder()
    let instruction = decoder.decode(0xd61f_0200, at: 0x1_0000_0000)

    XCTAssertEqual(instruction.mnemonic, "br")
    XCTAssertEqual(instruction.category, .branch)
  }

  func testDecodeBLR() throws {
    // BLR x8
    // Encoding: 0xd63f0100
    let decoder = InstructionDecoder()
    let instruction = decoder.decode(0xd63f_0100, at: 0x1_0000_0000)

    XCTAssertEqual(instruction.mnemonic, "blr")
    XCTAssertEqual(instruction.category, .branch)
  }

  func testDecodeRET() throws {
    // RET (defaults to x30)
    // Encoding: 0xd65f03c0
    let decoder = InstructionDecoder()
    let instruction = decoder.decode(0xd65f_03c0, at: 0x1_0000_0000)

    XCTAssertEqual(instruction.mnemonic, "ret")
    XCTAssertEqual(instruction.category, .branch)
  }

  func testDecodeCBZ() throws {
    // CBZ x0, #0x20
    // Encoding: 0xb4000100
    let decoder = InstructionDecoder()
    let instruction = decoder.decode(0xb400_0100, at: 0x1_0000_0000)

    XCTAssertEqual(instruction.mnemonic, "cbz")
    XCTAssertEqual(instruction.category, .branch)
  }

  func testDecodeCBNZ() throws {
    // CBNZ w1, #0x10
    // Encoding: 0x35000081
    let decoder = InstructionDecoder()
    let instruction = decoder.decode(0x3500_0081, at: 0x1_0000_0000)

    XCTAssertEqual(instruction.mnemonic, "cbnz")
    XCTAssertEqual(instruction.category, .branch)
  }

  // MARK: - Data Processing Instructions

  func testDecodeADDImmediate() throws {
    // ADD x0, x1, #0x10
    // Encoding: 0x91004020
    let decoder = InstructionDecoder()
    let instruction = decoder.decode(0x9100_4020, at: 0x1_0000_0000)

    XCTAssertEqual(instruction.mnemonic, "add")
    XCTAssertEqual(instruction.category, .dataProcessing)
  }

  func testDecodeSUBImmediate() throws {
    // SUB sp, sp, #0x20
    // Encoding: 0xd10083ff
    let decoder = InstructionDecoder()
    let instruction = decoder.decode(0xd100_83ff, at: 0x1_0000_0000)

    XCTAssertEqual(instruction.mnemonic, "sub")
    XCTAssertEqual(instruction.category, .dataProcessing)
  }

  func testDecodeMOVImmediate() throws {
    // MOV x0, #0
    // Encoding: 0xd2800000
    let decoder = InstructionDecoder()
    let instruction = decoder.decode(0xd280_0000, at: 0x1_0000_0000)

    XCTAssertEqual(instruction.mnemonic, "mov")
    XCTAssertEqual(instruction.category, .dataProcessing)
  }

  func testDecodeMOVRegister() throws {
    // MOV x29, sp
    // Encoding: 0x910003fd
    let decoder = InstructionDecoder()
    let instruction = decoder.decode(0x9100_03fd, at: 0x1_0000_0000)

    // This is actually ADD x29, sp, #0 which is an alias for MOV
    XCTAssertTrue(instruction.mnemonic == "mov" || instruction.mnemonic == "add")
    XCTAssertEqual(instruction.category, .dataProcessing)
  }

  func testDecodeADDRegister() throws {
    // ADD x0, x1, x2
    // Encoding: 0x8b020020
    let decoder = InstructionDecoder()
    let instruction = decoder.decode(0x8b02_0020, at: 0x1_0000_0000)

    XCTAssertEqual(instruction.mnemonic, "add")
    XCTAssertEqual(instruction.category, .dataProcessing)
  }

  func testDecodeSUBRegister() throws {
    // SUB x0, x1, x2
    // Encoding: 0xcb020020
    let decoder = InstructionDecoder()
    let instruction = decoder.decode(0xcb02_0020, at: 0x1_0000_0000)

    XCTAssertEqual(instruction.mnemonic, "sub")
    XCTAssertEqual(instruction.category, .dataProcessing)
  }

  func testDecodeANDRegister() throws {
    // AND x0, x1, x2
    // Encoding: 0x8a020020
    let decoder = InstructionDecoder()
    let instruction = decoder.decode(0x8a02_0020, at: 0x1_0000_0000)

    XCTAssertEqual(instruction.mnemonic, "and")
    XCTAssertEqual(instruction.category, .dataProcessing)
  }

  func testDecodeORRRegister() throws {
    // ORR x0, x1, x2
    // Encoding: 0xaa020020
    let decoder = InstructionDecoder()
    let instruction = decoder.decode(0xaa02_0020, at: 0x1_0000_0000)

    XCTAssertEqual(instruction.mnemonic, "orr")
    XCTAssertEqual(instruction.category, .dataProcessing)
  }

  func testDecodeCMP() throws {
    // CMP x0, #0
    // Encoding: 0xf100001f
    let decoder = InstructionDecoder()
    let instruction = decoder.decode(0xf100_001f, at: 0x1_0000_0000)

    // CMP is an alias for SUBS with Rd=xzr
    XCTAssertTrue(instruction.mnemonic == "cmp" || instruction.mnemonic == "subs")
    XCTAssertEqual(instruction.category, .dataProcessing)
  }

  // MARK: - Load/Store Instructions

  func testDecodeLDRImmediate() throws {
    // LDR x0, [x1, #0x10]
    // Encoding: 0xf9400820
    let decoder = InstructionDecoder()
    let instruction = decoder.decode(0xf940_0820, at: 0x1_0000_0000)

    XCTAssertEqual(instruction.mnemonic, "ldr")
    XCTAssertEqual(instruction.category, .loadStore)
  }

  func testDecodeSTRImmediate() throws {
    // STR x0, [sp, #0x10]
    // Encoding: 0xf90007e0
    let decoder = InstructionDecoder()
    let instruction = decoder.decode(0xf900_07e0, at: 0x1_0000_0000)

    XCTAssertEqual(instruction.mnemonic, "str")
    XCTAssertEqual(instruction.category, .loadStore)
  }

  func testDecodeLDRByte() throws {
    // LDRB w0, [x1]
    // Encoding: 0x39400020
    let decoder = InstructionDecoder()
    let instruction = decoder.decode(0x3940_0020, at: 0x1_0000_0000)

    XCTAssertEqual(instruction.mnemonic, "ldrb")
    XCTAssertEqual(instruction.category, .loadStore)
  }

  func testDecodeSTRByte() throws {
    // STRB w0, [x1]
    // Encoding: 0x39000020
    let decoder = InstructionDecoder()
    let instruction = decoder.decode(0x3900_0020, at: 0x1_0000_0000)

    XCTAssertEqual(instruction.mnemonic, "strb")
    XCTAssertEqual(instruction.category, .loadStore)
  }

  func testDecodeLDPPreIndex() throws {
    // LDP x29, x30, [sp, #-16]!
    // Encoding: 0xa9bf7bfd
    let decoder = InstructionDecoder()
    let instruction = decoder.decode(0xa9bf_7bfd, at: 0x1_0000_0000)

    // LDP with pre-index or STP
    XCTAssertTrue(instruction.mnemonic == "ldp" || instruction.mnemonic == "stp")
    XCTAssertEqual(instruction.category, .loadStore)
  }

  func testDecodeSTPPostIndex() throws {
    // STP x29, x30, [sp], #16
    // Encoding: 0xa8c17bfd
    let decoder = InstructionDecoder()
    let instruction = decoder.decode(0xa8c1_7bfd, at: 0x1_0000_0000)

    XCTAssertTrue(instruction.mnemonic == "ldp" || instruction.mnemonic == "stp")
    XCTAssertEqual(instruction.category, .loadStore)
  }

  func testDecodeLDRLiteral() throws {
    // LDR x0, <label> (PC-relative literal load)
    // Encoding: 0x58000040 (offset = 8 bytes)
    let decoder = InstructionDecoder()
    let instruction = decoder.decode(0x5800_0040, at: 0x1_0000_0000)

    XCTAssertEqual(instruction.mnemonic, "ldr")
    XCTAssertEqual(instruction.category, .loadStore)
  }

  func testDecodeADRP() throws {
    // ADRP x0, <page>
    // Encoding: 0x90000000
    let decoder = InstructionDecoder()
    let instruction = decoder.decode(0x9000_0000, at: 0x1_0000_0000)

    XCTAssertEqual(instruction.mnemonic, "adrp")
    XCTAssertEqual(instruction.category, .loadStore)
  }

  // MARK: - System Instructions

  func testDecodeNOP() throws {
    // NOP
    // Encoding: 0xd503201f
    let decoder = InstructionDecoder()
    let instruction = decoder.decode(0xd503_201f, at: 0x1_0000_0000)

    XCTAssertEqual(instruction.mnemonic, "nop")
    XCTAssertEqual(instruction.category, .system)
  }

  func testDecodeSVC() throws {
    // SVC #0x80
    // Encoding: 0xd4001001
    let decoder = InstructionDecoder()
    let instruction = decoder.decode(0xd400_1001, at: 0x1_0000_0000)

    XCTAssertEqual(instruction.mnemonic, "svc")
    XCTAssertEqual(instruction.category, .system)
  }

  func testDecodeBRK() throws {
    // BRK #0
    // Encoding: 0xd4200000
    let decoder = InstructionDecoder()
    let instruction = decoder.decode(0xd420_0000, at: 0x1_0000_0000)

    XCTAssertEqual(instruction.mnemonic, "brk")
    XCTAssertEqual(instruction.category, .system)
  }

  func testDecodeMSR() throws {
    // MSR NZCV, x0
    // Encoding: 0xd51b4200
    let decoder = InstructionDecoder()
    let instruction = decoder.decode(0xd51b_4200, at: 0x1_0000_0000)

    XCTAssertEqual(instruction.mnemonic, "msr")
    XCTAssertEqual(instruction.category, .system)
  }

  func testDecodeMRS() throws {
    // MRS x0, NZCV
    // Encoding: 0xd53b4200
    let decoder = InstructionDecoder()
    let instruction = decoder.decode(0xd53b_4200, at: 0x1_0000_0000)

    XCTAssertEqual(instruction.mnemonic, "mrs")
    XCTAssertEqual(instruction.category, .system)
  }

  // MARK: - Negative Offset Tests

  func testDecodeBranchBackward() throws {
    // B #-0x10 (branch backward)
    // Encoding: 0x17fffffc
    let decoder = InstructionDecoder()
    let instruction = decoder.decode(0x17ff_fffc, at: 0x1_0000_0010)

    XCTAssertEqual(instruction.mnemonic, "b")
    XCTAssertEqual(instruction.targetAddress, 0x1_0000_0000)
  }

  // MARK: - Edge Cases

  func testDecodeAtAddressZero() throws {
    let decoder = InstructionDecoder()
    // Decode a simple ADD instruction at address 0
    let instruction = decoder.decode(0x9100_4020, at: 0)

    XCTAssertEqual(instruction.mnemonic, "add")
    XCTAssertEqual(instruction.address, 0)
  }

  func testDecodeAtTypicalAddress() throws {
    let decoder = InstructionDecoder()
    // Use a typical macOS user-space address
    let typicalAddress: UInt64 = 0x1_0000_0000
    let instruction = decoder.decode(0x9100_4020, at: typicalAddress)

    XCTAssertEqual(instruction.mnemonic, "add")
    XCTAssertEqual(instruction.address, typicalAddress)
  }
}
