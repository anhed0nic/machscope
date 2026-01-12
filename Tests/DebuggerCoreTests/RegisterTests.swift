// RegisterTests.swift
// DebuggerCoreTests
//
// Unit tests for register reading and ARM64Registers

import XCTest

@testable import DebuggerCore

final class RegisterTests: XCTestCase {

  // MARK: - ARM64Registers Initialization Tests

  func testDefaultInitialization() {
    let regs = ARM64Registers()

    // All general purpose registers should be 0
    XCTAssertEqual(regs.x0, 0)
    XCTAssertEqual(regs.x1, 0)
    XCTAssertEqual(regs.x15, 0)
    XCTAssertEqual(regs.x28, 0)

    // Special registers
    XCTAssertEqual(regs.x29, 0)  // Frame pointer
    XCTAssertEqual(regs.x30, 0)  // Link register
    XCTAssertEqual(regs.sp, 0)  // Stack pointer
    XCTAssertEqual(regs.pc, 0)  // Program counter
    XCTAssertEqual(regs.cpsr, 0)  // Status register
  }

  func testRegisterMutation() {
    var regs = ARM64Registers()

    regs.x0 = 1
    regs.x1 = 0x7fff_5fbf_f400
    regs.pc = 0x1_0000_3f40
    regs.sp = 0x1_6fdf_f3e0

    XCTAssertEqual(regs.x0, 1)
    XCTAssertEqual(regs.x1, 0x7fff_5fbf_f400)
    XCTAssertEqual(regs.pc, 0x1_0000_3f40)
    XCTAssertEqual(regs.sp, 0x1_6fdf_f3e0)
  }

  // MARK: - Named Register Access Tests

  func testFramePointerAlias() {
    var regs = ARM64Registers()
    regs.x29 = 0x1_6fdf_f3f0

    XCTAssertEqual(regs.x29, 0x1_6fdf_f3f0)
    XCTAssertEqual(regs.fp, 0x1_6fdf_f3f0)
  }

  func testLinkRegisterAlias() {
    var regs = ARM64Registers()
    regs.x30 = 0x1_0000_3fa0

    XCTAssertEqual(regs.x30, 0x1_0000_3fa0)
    XCTAssertEqual(regs.lr, 0x1_0000_3fa0)
  }

  // MARK: - Register Subscript Tests

  func testRegisterSubscript() {
    var regs = ARM64Registers()
    regs.x5 = 0x1234_5678

    XCTAssertEqual(regs[5], 0x1234_5678)
  }

  func testRegisterSubscriptSet() {
    var regs = ARM64Registers()
    regs[7] = 0xDEAD_BEEF

    XCTAssertEqual(regs.x7, 0xDEAD_BEEF)
  }

  func testRegisterSubscriptRange() {
    var regs = ARM64Registers()

    // Test all general purpose registers 0-28
    for i in 0...28 {
      regs[i] = UInt64(i * 100)
    }

    for i in 0...28 {
      XCTAssertEqual(regs[i], UInt64(i * 100))
    }
  }

  // MARK: - CPSR Flag Tests

  func testCPSRNegativeFlag() {
    var regs = ARM64Registers()

    // N flag is bit 31
    regs.cpsr = 0x8000_0000
    XCTAssertTrue(regs.negativeFlag)

    regs.cpsr = 0
    XCTAssertFalse(regs.negativeFlag)
  }

  func testCPSRZeroFlag() {
    var regs = ARM64Registers()

    // Z flag is bit 30
    regs.cpsr = 0x4000_0000
    XCTAssertTrue(regs.zeroFlag)

    regs.cpsr = 0
    XCTAssertFalse(regs.zeroFlag)
  }

  func testCPSRCarryFlag() {
    var regs = ARM64Registers()

    // C flag is bit 29
    regs.cpsr = 0x2000_0000
    XCTAssertTrue(regs.carryFlag)

    regs.cpsr = 0
    XCTAssertFalse(regs.carryFlag)
  }

  func testCPSROverflowFlag() {
    var regs = ARM64Registers()

    // V flag is bit 28
    regs.cpsr = 0x1000_0000
    XCTAssertTrue(regs.overflowFlag)

    regs.cpsr = 0
    XCTAssertFalse(regs.overflowFlag)
  }

  func testCPSRMultipleFlags() {
    var regs = ARM64Registers()

    // Set N and Z flags (bits 31 and 30)
    regs.cpsr = 0xC000_0000
    XCTAssertTrue(regs.negativeFlag)
    XCTAssertTrue(regs.zeroFlag)
    XCTAssertFalse(regs.carryFlag)
    XCTAssertFalse(regs.overflowFlag)
  }

  func testCPSRFlagsDescription() {
    var regs = ARM64Registers()
    regs.cpsr = 0x6000_1000  // Z and C flags set

    let flags = regs.flagsDescription
    XCTAssertTrue(flags.contains("Z"))
    XCTAssertTrue(flags.contains("C"))
    XCTAssertFalse(flags.contains("N"))
    XCTAssertFalse(flags.contains("V"))
  }

  // MARK: - Register Description Tests

  func testRegisterDescription() {
    var regs = ARM64Registers()
    regs.x0 = 1
    regs.x1 = 0x7fff_5fbf_f400
    regs.pc = 0x1_0000_3f40
    regs.sp = 0x1_6fdf_f3e0
    regs.cpsr = 0x6000_1000

    let description = regs.description

    // Should contain register values
    XCTAssertTrue(description.contains("x0"))
    XCTAssertTrue(description.contains("x1"))
    XCTAssertTrue(description.contains("pc"))
    XCTAssertTrue(description.contains("sp"))
    XCTAssertTrue(description.contains("cpsr"))
  }

  func testRegisterSummary() {
    var regs = ARM64Registers()
    regs.pc = 0x1_0000_3f40
    regs.sp = 0x1_6fdf_f3e0
    regs.x29 = 0x1_6fdf_f3f0
    regs.x30 = 0x1_0000_3fa0

    let summary = regs.summary

    XCTAssertTrue(summary.contains("pc"))
    XCTAssertTrue(summary.contains("sp"))
  }

  // MARK: - Sendable Conformance Test

  func testSendableConformance() async {
    let regs = ARM64Registers()

    // This should compile without issues due to Sendable conformance
    await withTaskGroup(of: UInt64.self) { group in
      group.addTask {
        return regs.pc
      }
      for await _ in group {}
    }
  }

  // MARK: - Codable Tests

  func testCodable() throws {
    var regs = ARM64Registers()
    regs.x0 = 0x123
    regs.pc = 0x1_0000_3f40
    regs.cpsr = 0x6000_0000

    let encoder = JSONEncoder()
    let data = try encoder.encode(regs)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(ARM64Registers.self, from: data)

    XCTAssertEqual(decoded.x0, 0x123)
    XCTAssertEqual(decoded.pc, 0x1_0000_3f40)
    XCTAssertEqual(decoded.cpsr, 0x6000_0000)
  }

  // MARK: - Register Count Tests

  func testRegisterCount() {
    // ARM64 has 31 general purpose registers (x0-x30)
    XCTAssertEqual(ARM64Registers.generalPurposeCount, 31)
  }

  // MARK: - Zero Register Tests

  func testZeroRegisterBehavior() {
    // In ARM64, xzr (x31) always reads as zero
    // Our implementation doesn't include x31 as a stored register
    // but we can test the constant
    XCTAssertEqual(ARM64Registers.zeroRegisterValue, 0)
  }
}

// MARK: - Thread State Tests

extension RegisterTests {

  func testThreadStateCreation() {
    let state = ThreadState(
      threadID: 0x1234,
      registers: ARM64Registers(),
      isSuspended: false
    )

    XCTAssertEqual(state.threadID, 0x1234)
    XCTAssertFalse(state.isSuspended)
  }

  func testThreadStateWithRegisters() {
    var regs = ARM64Registers()
    regs.pc = 0x1_0000_3f40
    regs.sp = 0x1_6fdf_f3e0

    let state = ThreadState(
      threadID: 0x5678,
      registers: regs,
      isSuspended: true
    )

    XCTAssertEqual(state.registers.pc, 0x1_0000_3f40)
    XCTAssertEqual(state.registers.sp, 0x1_6fdf_f3e0)
    XCTAssertTrue(state.isSuspended)
  }
}
