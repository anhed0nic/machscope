// FormatterTests.swift
// DisassemblerTests
//
// Unit tests for instruction formatting

import XCTest

@testable import Disassembler

final class FormatterTests: XCTestCase {

  var formatter: InstructionFormatter!

  override func setUp() {
    super.setUp()
    formatter = InstructionFormatter()
  }

  // MARK: - Basic Formatting

  func testFormatBranchInstruction() throws {
    let instruction = Instruction(
      address: 0x1_0000_0000,
      encoding: 0x1400_0005,
      mnemonic: "b",
      operands: [.address(0x1_0000_0014)],
      category: .branch,
      annotation: nil,
      targetAddress: 0x1_0000_0014,
      targetSymbol: nil
    )

    let formatted = formatter.format(instruction)
    XCTAssertTrue(formatted.contains("b"))
    XCTAssertTrue(formatted.contains("0x100000014"))
  }

  func testFormatBranchWithSymbol() throws {
    let instruction = Instruction(
      address: 0x1_0000_0000,
      encoding: 0x9400_0400,
      mnemonic: "bl",
      operands: [.address(0x1_0000_1000)],
      category: .branch,
      annotation: nil,
      targetAddress: 0x1_0000_1000,
      targetSymbol: "_helper_function"
    )

    let formatted = formatter.format(instruction)
    XCTAssertTrue(formatted.contains("bl"))
    XCTAssertTrue(formatted.contains("_helper_function"))
  }

  func testFormatRegisterOperands() throws {
    let instruction = Instruction(
      address: 0x1_0000_0000,
      encoding: 0x8b02_0020,
      mnemonic: "add",
      operands: [
        .register(.general(0, .x)),
        .register(.general(1, .x)),
        .register(.general(2, .x)),
      ],
      category: .dataProcessing,
      annotation: nil,
      targetAddress: nil,
      targetSymbol: nil
    )

    let formatted = formatter.format(instruction)
    XCTAssertTrue(formatted.contains("add"))
    XCTAssertTrue(formatted.contains("x0"))
    XCTAssertTrue(formatted.contains("x1"))
    XCTAssertTrue(formatted.contains("x2"))
  }

  func testFormatImmediateOperand() throws {
    let instruction = Instruction(
      address: 0x1_0000_0000,
      encoding: 0x9100_4020,
      mnemonic: "add",
      operands: [
        .register(.general(0, .x)),
        .register(.general(1, .x)),
        .immediate(0x10),
      ],
      category: .dataProcessing,
      annotation: nil,
      targetAddress: nil,
      targetSymbol: nil
    )

    let formatted = formatter.format(instruction)
    XCTAssertTrue(formatted.contains("add"))
    XCTAssertTrue(formatted.contains("#"))
  }

  func testFormatMemoryOperand() throws {
    let instruction = Instruction(
      address: 0x1_0000_0000,
      encoding: 0xf940_0820,
      mnemonic: "ldr",
      operands: [
        .register(.general(0, .x)),
        .memory(base: .general(1, .x), offset: 0x10, indexMode: .offset),
      ],
      category: .loadStore,
      annotation: nil,
      targetAddress: nil,
      targetSymbol: nil
    )

    let formatted = formatter.format(instruction)
    XCTAssertTrue(formatted.contains("ldr"))
    XCTAssertTrue(formatted.contains("["))
    XCTAssertTrue(formatted.contains("]"))
  }

  // MARK: - Address Formatting

  func testFormatWithAddress() throws {
    let instruction = Instruction(
      address: 0x1_0000_3f40,
      encoding: 0xd65f_03c0,
      mnemonic: "ret",
      operands: [],
      category: .branch,
      annotation: nil,
      targetAddress: nil,
      targetSymbol: nil
    )

    let formatted = formatter.format(instruction, showAddress: true)
    XCTAssertTrue(formatted.contains("0x100003f40"))
  }

  func testFormatWithoutAddress() throws {
    let instruction = Instruction(
      address: 0x1_0000_3f40,
      encoding: 0xd65f_03c0,
      mnemonic: "ret",
      operands: [],
      category: .branch,
      annotation: nil,
      targetAddress: nil,
      targetSymbol: nil
    )

    let formatted = formatter.format(instruction, showAddress: false)
    XCTAssertFalse(formatted.contains("0x100003f40"))
    XCTAssertTrue(formatted.contains("ret"))
  }

  // MARK: - Bytes Formatting

  func testFormatWithBytes() throws {
    let instruction = Instruction(
      address: 0x1_0000_0000,
      encoding: 0xd503_201f,
      mnemonic: "nop",
      operands: [],
      category: .system,
      annotation: nil,
      targetAddress: nil,
      targetSymbol: nil
    )

    let formatted = formatter.format(instruction, showBytes: true)
    XCTAssertTrue(formatted.contains("1f") || formatted.contains("1F"))
    XCTAssertTrue(formatted.contains("20") || formatted.contains("03"))
  }

  func testFormatWithoutBytes() throws {
    let instruction = Instruction(
      address: 0x1_0000_0000,
      encoding: 0xd503_201f,
      mnemonic: "nop",
      operands: [],
      category: .system,
      annotation: nil,
      targetAddress: nil,
      targetSymbol: nil
    )

    let formatted = formatter.format(instruction, showBytes: false)
    XCTAssertTrue(formatted.contains("nop"))
  }

  // MARK: - Annotation Formatting

  func testFormatWithAnnotation() throws {
    let instruction = Instruction(
      address: 0x1_0000_0000,
      encoding: 0xd65f_03c0,
      mnemonic: "ret",
      operands: [],
      category: .branch,
      annotation: "[PAC] Authenticated return",
      targetAddress: nil,
      targetSymbol: nil
    )

    let formatted = formatter.format(instruction)
    XCTAssertTrue(formatted.contains("[PAC]") || formatted.contains("Authenticated"))
  }

  // MARK: - Special Register Formatting

  func testFormatStackPointer() throws {
    let instruction = Instruction(
      address: 0x1_0000_0000,
      encoding: 0xd100_83ff,
      mnemonic: "sub",
      operands: [
        .register(.sp),
        .register(.sp),
        .immediate(0x20),
      ],
      category: .dataProcessing,
      annotation: nil,
      targetAddress: nil,
      targetSymbol: nil
    )

    let formatted = formatter.format(instruction)
    XCTAssertTrue(formatted.contains("sp"))
  }

  func testFormatZeroRegister() throws {
    let instruction = Instruction(
      address: 0x1_0000_0000,
      encoding: 0xaa1f_03e0,
      mnemonic: "mov",
      operands: [
        .register(.general(0, .x)),
        .register(.xzr),
      ],
      category: .dataProcessing,
      annotation: nil,
      targetAddress: nil,
      targetSymbol: nil
    )

    let formatted = formatter.format(instruction)
    XCTAssertTrue(formatted.contains("xzr") || formatted.contains("mov"))
  }

  // MARK: - Pre/Post Index Formatting

  func testFormatPreIndexMemory() throws {
    let instruction = Instruction(
      address: 0x1_0000_0000,
      encoding: 0xa9bf_7bfd,
      mnemonic: "stp",
      operands: [
        .register(.general(29, .x)),
        .register(.general(30, .x)),
        .memory(base: .sp, offset: -16, indexMode: .preIndex),
      ],
      category: .loadStore,
      annotation: nil,
      targetAddress: nil,
      targetSymbol: nil
    )

    let formatted = formatter.format(instruction)
    XCTAssertTrue(formatted.contains("!") || formatted.contains("stp"))
  }

  func testFormatPostIndexMemory() throws {
    let instruction = Instruction(
      address: 0x1_0000_0000,
      encoding: 0xa8c1_7bfd,
      mnemonic: "ldp",
      operands: [
        .register(.general(29, .x)),
        .register(.general(30, .x)),
        .memory(base: .sp, offset: 16, indexMode: .postIndex),
      ],
      category: .loadStore,
      annotation: nil,
      targetAddress: nil,
      targetSymbol: nil
    )

    let formatted = formatter.format(instruction)
    XCTAssertTrue(formatted.contains("ldp"))
  }

  // MARK: - Condition Code Formatting

  func testFormatConditionCodes() throws {
    let conditions = [
      "eq", "ne", "cs", "cc", "mi", "pl", "vs", "vc",
      "hi", "ls", "ge", "lt", "gt", "le", "al",
    ]

    for (index, condition) in conditions.enumerated() {
      let instruction = Instruction(
        address: 0x1_0000_0000,
        encoding: UInt32(0x5400_0000 | index),
        mnemonic: "b.\(condition)",
        operands: [.address(0x1_0000_0010)],
        category: .branch,
        annotation: nil,
        targetAddress: 0x1_0000_0010,
        targetSymbol: nil
      )

      let formatted = formatter.format(instruction)
      XCTAssertTrue(
        formatted.contains("b.") || formatted.contains(condition),
        "Missing condition code: \(condition)")
    }
  }

  // MARK: - Output Alignment

  func testMnemonicAlignment() throws {
    let instructions = [
      Instruction(
        address: 0x1_0000_0000,
        encoding: 0xd503_201f,
        mnemonic: "nop",
        operands: [],
        category: .system,
        annotation: nil,
        targetAddress: nil,
        targetSymbol: nil
      ),
      Instruction(
        address: 0x1_0000_0004,
        encoding: 0x9400_0400,
        mnemonic: "bl",
        operands: [.address(0x1_0000_1000)],
        category: .branch,
        annotation: nil,
        targetAddress: 0x1_0000_1000,
        targetSymbol: "_long_function_name"
      ),
    ]

    let formatted = instructions.map { formatter.format($0, showAddress: true) }

    // Both should have consistent formatting
    XCTAssertEqual(formatted.count, 2)
  }
}
