// HeaderTests.swift
// MachOKitTests
//
// Unit tests for MachHeader parsing

import XCTest

@testable import MachOKit

final class HeaderTests: XCTestCase {

  // MARK: - Test Fixtures Path

  private var fixturesPath: String {
    // Get the path relative to the source file
    // #filePath gives the full path to this source file
    let currentFile = #filePath
    let testsDir = URL(fileURLWithPath: currentFile)
      .deletingLastPathComponent()  // Remove filename (HeaderTests.swift)
    return testsDir.appendingPathComponent("Fixtures").path
  }

  private var simpleARM64Path: String {
    fixturesPath + "/simple_arm64"
  }

  // MARK: - Valid Header Tests

  func testValidMachOHeader() throws {
    // Load the simple_arm64 fixture
    let reader = try loadBinary(at: simpleARM64Path)

    // Parse the header
    let header = try MachHeader.parse(from: reader)

    // Verify magic number
    XCTAssertEqual(header.magic, MachOMagic.mh64.rawValue, "Magic should be 64-bit Mach-O")

    // Verify CPU type
    XCTAssertEqual(header.cpuType, .arm64, "CPU type should be ARM64")

    // Verify file type is executable
    XCTAssertEqual(header.fileType, .execute, "File type should be executable")

    // Verify we have load commands
    XCTAssertGreaterThan(header.numberOfCommands, 0, "Should have at least one load command")
    XCTAssertGreaterThan(header.sizeOfCommands, 0, "Size of commands should be > 0")
  }

  func testHeaderCPUSubtype() throws {
    let reader = try loadBinary(at: simpleARM64Path)
    let header = try MachHeader.parse(from: reader)

    // ARM64 subtype should be all or arm64e
    let validSubtypes: [CPUSubtype] = [.all, .arm64e, .arm64v8]
    XCTAssertTrue(
      validSubtypes.contains(header.cpuSubtype),
      "CPU subtype should be a valid ARM64 subtype")
  }

  func testHeaderFlags() throws {
    let reader = try loadBinary(at: simpleARM64Path)
    let header = try MachHeader.parse(from: reader)

    // Executables typically have these flags
    XCTAssertTrue(
      header.flags.contains(.dynamicLink),
      "Executable should be dynamically linked")
  }

  // MARK: - Invalid Header Tests

  func testInvalidMagicNumber() throws {
    // Create data with invalid magic
    let invalidData = Data([0x00, 0x00, 0x00, 0x00] + Array(repeating: UInt8(0), count: 28))
    let reader = BinaryReader(data: invalidData)

    XCTAssertThrowsError(try MachHeader.parse(from: reader)) { error in
      guard case MachOParseError.invalidMagic(let found, _) = error else {
        XCTFail("Expected invalidMagic error, got \(error)")
        return
      }
      XCTAssertEqual(found, 0, "Should report the invalid magic value")
    }
  }

  func testTruncatedHeader() throws {
    // Create data too short for a header
    let truncatedData = Data([0xCF, 0xFA, 0xED, 0xFE])  // Just magic, no rest
    let reader = BinaryReader(data: truncatedData)

    XCTAssertThrowsError(try MachHeader.parse(from: reader)) { error in
      guard case MachOParseError.insufficientData = error else {
        XCTFail("Expected insufficientData error, got \(error)")
        return
      }
    }
  }

  // MARK: - Header Size Tests

  func testHeader64Size() {
    XCTAssertEqual(MachHeader.size64, 32, "64-bit header should be 32 bytes")
  }

  func testHeader32Size() {
    XCTAssertEqual(MachHeader.size32, 28, "32-bit header should be 28 bytes")
  }

  // MARK: - Magic Number Tests

  func testMachOMagicIs64Bit() {
    XCTAssertTrue(MachOMagic.mh64.is64Bit)
    XCTAssertTrue(MachOMagic.mh64Cigam.is64Bit)
    XCTAssertFalse(MachOMagic.mh32.is64Bit)
    XCTAssertFalse(MachOMagic.fat.is64Bit)
  }

  func testMachOMagicIsFat() {
    XCTAssertTrue(MachOMagic.fat.isFat)
    XCTAssertTrue(MachOMagic.fatCigam.isFat)
    XCTAssertTrue(MachOMagic.fat64.isFat)
    XCTAssertFalse(MachOMagic.mh64.isFat)
  }

  func testMachOMagicNeedsByteSwap() {
    XCTAssertTrue(MachOMagic.mh64Cigam.needsByteSwap)
    XCTAssertTrue(MachOMagic.fatCigam.needsByteSwap)
    XCTAssertFalse(MachOMagic.mh64.needsByteSwap)
    XCTAssertFalse(MachOMagic.fat.needsByteSwap)
  }

  // MARK: - CPU Type Tests

  func testCPUTypeDescription() {
    XCTAssertEqual(CPUType.arm64.description, "arm64")
    XCTAssertEqual(CPUType.x86_64.description, "x86_64")
  }

  func testCPUTypeIs64Bit() {
    XCTAssertTrue(CPUType.arm64.is64Bit)
    XCTAssertTrue(CPUType.x86_64.is64Bit)
    XCTAssertFalse(CPUType.arm.is64Bit)
    XCTAssertFalse(CPUType.x86.is64Bit)
  }

  func testCPUTypeIsSupported() {
    XCTAssertTrue(CPUType.arm64.isSupported)
    XCTAssertFalse(CPUType.x86_64.isSupported)
  }

  // MARK: - File Type Tests

  func testFileTypeDescription() {
    XCTAssertEqual(FileType.execute.description, "execute")
    XCTAssertEqual(FileType.dylib.description, "dylib")
    XCTAssertEqual(FileType.bundle.description, "bundle")
  }

  func testFileTypeDisplayName() {
    XCTAssertEqual(FileType.execute.displayName, "Executable")
    XCTAssertEqual(FileType.dylib.displayName, "Dynamic Library")
  }

  // MARK: - Header Flags Tests

  func testHeaderFlagsOptionSet() {
    var flags = MachHeaderFlags()
    flags.insert(.pie)
    flags.insert(.twolevel)

    XCTAssertTrue(flags.contains(.pie))
    XCTAssertTrue(flags.contains(.twolevel))
    XCTAssertFalse(flags.contains(.prebound))
  }

  func testHeaderFlagNames() {
    let flags: MachHeaderFlags = [.pie, .twolevel, .dynamicLink]
    let names = flags.flagNames

    XCTAssertTrue(names.contains("PIE"))
    XCTAssertTrue(names.contains("TWOLEVEL"))
    XCTAssertTrue(names.contains("DYLDLINK"))
  }
}
