// SegmentTests.swift
// MachOKitTests
//
// Unit tests for Segment and Section parsing

import XCTest

@testable import MachOKit

final class SegmentTests: XCTestCase {

  // MARK: - Test Fixtures Path

  private var fixturesPath: String {
    let currentFile = #filePath
    let testsDir = URL(fileURLWithPath: currentFile)
      .deletingLastPathComponent()
    return testsDir.appendingPathComponent("Fixtures").path
  }

  private var simpleARM64Path: String {
    fixturesPath + "/simple_arm64"
  }

  // MARK: - Segment Parsing Tests

  func testParseSegments() throws {
    let binary = try MachOBinary(path: simpleARM64Path)
    let segments = binary.segments

    XCTAssertGreaterThan(segments.count, 0, "Should have at least one segment")

    // Typical executables have __PAGEZERO, __TEXT, __DATA, __LINKEDIT
    let segmentNames = segments.map { $0.name }
    XCTAssertTrue(segmentNames.contains("__TEXT"), "Should have __TEXT segment")
  }

  func testPageZeroSegment() throws {
    let binary = try MachOBinary(path: simpleARM64Path)

    guard let pageZero = binary.segments.first(where: { $0.name == "__PAGEZERO" }) else {
      // Some binaries may not have __PAGEZERO
      return
    }

    // __PAGEZERO is typically at address 0 with no file size
    XCTAssertEqual(pageZero.vmAddress, 0, "PAGEZERO should be at address 0")
    XCTAssertEqual(pageZero.fileSize, 0, "PAGEZERO should have no file data")
    XCTAssertGreaterThan(pageZero.vmSize, 0, "PAGEZERO should have non-zero VM size")
  }

  func testTextSegment() throws {
    let binary = try MachOBinary(path: simpleARM64Path)

    guard let text = binary.segments.first(where: { $0.name == "__TEXT" }) else {
      XCTFail("Should have __TEXT segment")
      return
    }

    // __TEXT segment should be readable and executable
    XCTAssertTrue(
      text.initialProtection.contains(.read),
      "__TEXT should be readable")
    XCTAssertTrue(
      text.initialProtection.contains(.execute),
      "__TEXT should be executable")
    XCTAssertFalse(
      text.initialProtection.contains(.write),
      "__TEXT should not be writable")
  }

  // MARK: - Section Parsing Tests

  func testParseSections() throws {
    let binary = try MachOBinary(path: simpleARM64Path)

    guard let text = binary.segments.first(where: { $0.name == "__TEXT" }) else {
      XCTFail("Should have __TEXT segment")
      return
    }

    XCTAssertGreaterThan(
      text.sections.count, 0,
      "__TEXT should have at least one section")

    // Should have __text section with code
    let hasTextSection = text.sections.contains { $0.name == "__text" }
    XCTAssertTrue(hasTextSection, "Should have __text section")
  }

  func testTextSectionAttributes() throws {
    let binary = try MachOBinary(path: simpleARM64Path)

    guard let text = binary.segments.first(where: { $0.name == "__TEXT" }),
      let textSection = text.sections.first(where: { $0.name == "__text" })
    else {
      XCTFail("Should have __TEXT.__text section")
      return
    }

    // Verify segment name matches
    XCTAssertEqual(textSection.segmentName, "__TEXT")

    // Code section should have non-zero size
    XCTAssertGreaterThan(textSection.size, 0, "__text section should have code")
  }

  // MARK: - VM Protection Tests

  func testVMProtectionFlags() {
    var protection = VMProtection()

    protection.insert(.read)
    XCTAssertTrue(protection.contains(.read))
    XCTAssertFalse(protection.contains(.write))
    XCTAssertFalse(protection.contains(.execute))

    protection.insert(.execute)
    XCTAssertTrue(protection.contains(.execute))

    protection.insert(.write)
    XCTAssertTrue(protection.isReadWriteExecute)
  }

  func testVMProtectionDescription() {
    let readOnly: VMProtection = [.read]
    XCTAssertEqual(readOnly.description, "r--")

    let readExec: VMProtection = [.read, .execute]
    XCTAssertEqual(readExec.description, "r-x")

    let readWrite: VMProtection = [.read, .write]
    XCTAssertEqual(readWrite.description, "rw-")

    let all: VMProtection = [.read, .write, .execute]
    XCTAssertEqual(all.description, "rwx")
  }

  // MARK: - Section Type Tests

  func testSectionTypeRawValues() {
    XCTAssertEqual(SectionType.regular.rawValue, 0x00)
    XCTAssertEqual(SectionType.zeroFill.rawValue, 0x01)
    XCTAssertEqual(SectionType.cstringLiterals.rawValue, 0x02)
    XCTAssertEqual(SectionType.symbolStubs.rawValue, 0x08)
  }

  func testSectionTypeFromMask() {
    // Section type is in lower 8 bits
    let flags: UInt32 = 0x8000_0002  // Some attrs + cstringLiterals
    let sectionType = SectionType.fromFlags(flags)
    XCTAssertEqual(sectionType, .cstringLiterals)
  }

  // MARK: - Segment Method Tests

  func testSegmentContainsAddress() throws {
    let binary = try MachOBinary(path: simpleARM64Path)

    guard let text = binary.segments.first(where: { $0.name == "__TEXT" }) else {
      XCTFail("Should have __TEXT segment")
      return
    }

    let startAddr = text.vmAddress
    let midAddr = text.vmAddress + text.vmSize / 2
    let endAddr = text.vmAddress + text.vmSize

    XCTAssertTrue(text.contains(address: startAddr), "Should contain start address")
    XCTAssertTrue(text.contains(address: midAddr), "Should contain middle address")
    XCTAssertFalse(text.contains(address: endAddr), "Should not contain end address (exclusive)")
  }

  func testSegmentFindSection() throws {
    let binary = try MachOBinary(path: simpleARM64Path)

    guard let text = binary.segments.first(where: { $0.name == "__TEXT" }) else {
      XCTFail("Should have __TEXT segment")
      return
    }

    let textSection = text.section(named: "__text")
    XCTAssertNotNil(textSection, "Should find __text section")

    let nonExistent = text.section(named: "__nonexistent")
    XCTAssertNil(nonExistent, "Should not find non-existent section")
  }
}
