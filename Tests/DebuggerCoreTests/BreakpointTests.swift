// BreakpointTests.swift
// DebuggerCoreTests
//
// Unit tests for breakpoint management

import XCTest

@testable import DebuggerCore

final class BreakpointTests: XCTestCase {

  // MARK: - Breakpoint Model Tests

  func testBreakpointCreation() {
    let bp = Breakpoint(
      id: 1,
      address: 0x1_0000_3f40,
      originalBytes: 0xa9bf_7bfd,
      isEnabled: true,
      hitCount: 0,
      symbol: "_main"
    )

    XCTAssertEqual(bp.id, 1)
    XCTAssertEqual(bp.address, 0x1_0000_3f40)
    XCTAssertEqual(bp.originalBytes, 0xa9bf_7bfd)
    XCTAssertTrue(bp.isEnabled)
    XCTAssertEqual(bp.hitCount, 0)
    XCTAssertEqual(bp.symbol, "_main")
  }

  func testBreakpointWithoutSymbol() {
    let bp = Breakpoint(
      id: 2,
      address: 0x1_0000_4000,
      originalBytes: 0xd503_201f,
      isEnabled: false,
      hitCount: 5,
      symbol: nil
    )

    XCTAssertEqual(bp.id, 2)
    XCTAssertNil(bp.symbol)
    XCTAssertFalse(bp.isEnabled)
    XCTAssertEqual(bp.hitCount, 5)
  }

  func testBreakpointAddressFormatting() {
    let bp = Breakpoint(
      id: 1,
      address: 0x1_0000_3f40,
      originalBytes: 0,
      isEnabled: true,
      hitCount: 0,
      symbol: nil
    )

    let hexAddress = String(bp.address, radix: 16)
    XCTAssertEqual(hexAddress, "100003f40")
  }

  // MARK: - BreakpointManager Tests

  func testBreakpointManagerCreation() {
    let manager = BreakpointManager()
    XCTAssertTrue(manager.breakpoints.isEmpty)
    XCTAssertEqual(manager.count, 0)
  }

  func testAddBreakpoint() throws {
    let manager = BreakpointManager()
    let id = try manager.addBreakpoint(at: 0x1_0000_3f40, symbol: "_main")

    XCTAssertEqual(id, 1)
    XCTAssertEqual(manager.count, 1)

    let bp = manager.breakpoint(id: 1)
    XCTAssertNotNil(bp)
    XCTAssertEqual(bp?.address, 0x1_0000_3f40)
    XCTAssertEqual(bp?.symbol, "_main")
    XCTAssertTrue(bp?.isEnabled ?? false)
  }

  func testAddMultipleBreakpoints() throws {
    let manager = BreakpointManager()

    let id1 = try manager.addBreakpoint(at: 0x1_0000_3f40, symbol: "_main")
    let id2 = try manager.addBreakpoint(at: 0x1_0000_3f60, symbol: "_helper")
    let id3 = try manager.addBreakpoint(at: 0x1_0000_3f80, symbol: nil)

    XCTAssertEqual(id1, 1)
    XCTAssertEqual(id2, 2)
    XCTAssertEqual(id3, 3)
    XCTAssertEqual(manager.count, 3)
  }

  func testRemoveBreakpoint() throws {
    let manager = BreakpointManager()
    let id = try manager.addBreakpoint(at: 0x1_0000_3f40, symbol: "_main")

    XCTAssertEqual(manager.count, 1)

    try manager.removeBreakpoint(id: id)
    XCTAssertEqual(manager.count, 0)
    XCTAssertNil(manager.breakpoint(id: id))
  }

  func testRemoveNonexistentBreakpoint() {
    let manager = BreakpointManager()

    XCTAssertThrowsError(try manager.removeBreakpoint(id: 999)) { error in
      guard let debuggerError = error as? DebuggerError,
        case .breakpointNotFound(let id) = debuggerError
      else {
        XCTFail("Expected breakpointNotFound error")
        return
      }
      XCTAssertEqual(id, 999)
    }
  }

  func testEnableDisableBreakpoint() throws {
    let manager = BreakpointManager()
    let id = try manager.addBreakpoint(at: 0x1_0000_3f40, symbol: "_main")

    // Initially enabled
    var bp = manager.breakpoint(id: id)
    XCTAssertTrue(bp?.isEnabled ?? false)

    // Disable
    try manager.disableBreakpoint(id: id)
    bp = manager.breakpoint(id: id)
    XCTAssertFalse(bp?.isEnabled ?? true)

    // Enable
    try manager.enableBreakpoint(id: id)
    bp = manager.breakpoint(id: id)
    XCTAssertTrue(bp?.isEnabled ?? false)
  }

  func testBreakpointByAddress() throws {
    let manager = BreakpointManager()
    _ = try manager.addBreakpoint(at: 0x1_0000_3f40, symbol: "_main")
    _ = try manager.addBreakpoint(at: 0x1_0000_3f60, symbol: "_helper")

    let bp = manager.breakpoint(at: 0x1_0000_3f60)
    XCTAssertNotNil(bp)
    XCTAssertEqual(bp?.symbol, "_helper")

    let notFound = manager.breakpoint(at: 0x999999)
    XCTAssertNil(notFound)
  }

  func testRecordHit() throws {
    let manager = BreakpointManager()
    let id = try manager.addBreakpoint(at: 0x1_0000_3f40, symbol: "_main")

    var bp = manager.breakpoint(id: id)
    XCTAssertEqual(bp?.hitCount, 0)

    manager.recordHit(id: id)
    bp = manager.breakpoint(id: id)
    XCTAssertEqual(bp?.hitCount, 1)

    manager.recordHit(id: id)
    manager.recordHit(id: id)
    bp = manager.breakpoint(id: id)
    XCTAssertEqual(bp?.hitCount, 3)
  }

  func testAllBreakpoints() throws {
    let manager = BreakpointManager()
    _ = try manager.addBreakpoint(at: 0x1_0000_3f40, symbol: "_main")
    _ = try manager.addBreakpoint(at: 0x1_0000_3f60, symbol: "_helper")

    let all = manager.breakpoints
    XCTAssertEqual(all.count, 2)
  }

  func testEnabledBreakpoints() throws {
    let manager = BreakpointManager()
    let id1 = try manager.addBreakpoint(at: 0x1_0000_3f40, symbol: "_main")
    _ = try manager.addBreakpoint(at: 0x1_0000_3f60, symbol: "_helper")

    try manager.disableBreakpoint(id: id1)

    let enabled = manager.enabledBreakpoints
    XCTAssertEqual(enabled.count, 1)
    XCTAssertEqual(enabled.first?.symbol, "_helper")
  }

  func testClearAllBreakpoints() throws {
    let manager = BreakpointManager()
    _ = try manager.addBreakpoint(at: 0x1_0000_3f40, symbol: "_main")
    _ = try manager.addBreakpoint(at: 0x1_0000_3f60, symbol: "_helper")

    XCTAssertEqual(manager.count, 2)

    manager.clearAll()
    XCTAssertEqual(manager.count, 0)
    XCTAssertTrue(manager.breakpoints.isEmpty)
  }

  // MARK: - ARM64 Breakpoint Instruction Tests

  func testARM64BreakpointInstruction() {
    // ARM64 BRK #0 instruction is 0xD4200000
    let brkInstruction = ARM64BreakpointInstruction.brk0
    XCTAssertEqual(brkInstruction, 0xD420_0000)
  }

  func testBreakpointInstructionSize() {
    // ARM64 instructions are fixed 32-bit (4 bytes)
    XCTAssertEqual(ARM64BreakpointInstruction.size, 4)
  }
}

// MARK: - Breakpoint Description Tests

extension BreakpointTests {

  func testBreakpointDescription() {
    let bp = Breakpoint(
      id: 1,
      address: 0x1_0000_3f40,
      originalBytes: 0xa9bf_7bfd,
      isEnabled: true,
      hitCount: 3,
      symbol: "_main"
    )

    let description = bp.description
    XCTAssertTrue(description.contains("1"))
    XCTAssertTrue(description.contains("100003f40"))
    XCTAssertTrue(description.contains("_main"))
  }

  func testBreakpointDescriptionWithoutSymbol() {
    let bp = Breakpoint(
      id: 2,
      address: 0x1_0000_4000,
      originalBytes: 0xd503_201f,
      isEnabled: false,
      hitCount: 0,
      symbol: nil
    )

    let description = bp.description
    XCTAssertTrue(description.contains("2"))
    XCTAssertTrue(description.contains("100004000"))
    XCTAssertFalse(description.contains("nil"))
  }
}
