// FatBinaryTests.swift
// MachOKitTests
//
// Unit tests for Fat/Universal binary detection and slice extraction

import XCTest

@testable import MachOKit

final class FatBinaryTests: XCTestCase {

  // MARK: - Test Fixtures Path

  private var fixturesPath: String {
    let currentFile = #filePath
    let testsDir = URL(fileURLWithPath: currentFile)
      .deletingLastPathComponent()
    return testsDir.appendingPathComponent("Fixtures").path
  }

  private var fatBinaryPath: String {
    fixturesPath + "/fat_binary"
  }

  private var simpleARM64Path: String {
    fixturesPath + "/simple_arm64"
  }

  // MARK: - Fat Binary Detection Tests

  func testDetectFatBinary() throws {
    let reader = try loadBinary(at: fatBinaryPath)
    let magic = try reader.readUInt32(at: 0)

    // Fat binary magic is 0xCAFEBABE (big-endian)
    let isFat =
      magic == MachOMagic.fat.rawValue || magic == MachOMagic.fatCigam.rawValue
      || magic == MachOMagic.fat64.rawValue || magic == MachOMagic.fat64Cigam.rawValue

    XCTAssertTrue(isFat, "Should detect fat binary magic")
  }

  func testDetectNonFatBinary() throws {
    let reader = try loadBinary(at: simpleARM64Path)
    let magic = try reader.readUInt32(at: 0)

    guard let machMagic = MachOMagic(rawValue: magic) else {
      XCTFail("Should have valid magic")
      return
    }

    XCTAssertFalse(machMagic.isFat, "Simple binary should not be fat")
    XCTAssertTrue(machMagic.is64Bit, "Should be 64-bit")
  }

  // MARK: - Fat Header Parsing Tests

  func testParseFatHeader() throws {
    let reader = try loadBinary(at: fatBinaryPath)
    let fatHeader = try FatHeader.parse(from: reader)

    XCTAssertGreaterThan(
      fatHeader.architectures.count, 0,
      "Fat binary should have at least one architecture")
  }

  func testFatBinaryArchitectures() throws {
    let reader = try loadBinary(at: fatBinaryPath)
    let fatHeader = try FatHeader.parse(from: reader)

    // Our test fat binary has arm64 and x86_64
    let cpuTypes = fatHeader.architectures.map { $0.cpuType }

    XCTAssertTrue(cpuTypes.contains(.arm64), "Should contain arm64 slice")
    XCTAssertTrue(cpuTypes.contains(.x86_64), "Should contain x86_64 slice")
  }

  // MARK: - Slice Extraction Tests

  func testExtractARM64Slice() throws {
    let reader = try loadBinary(at: fatBinaryPath)
    let fatHeader = try FatHeader.parse(from: reader)

    guard let arm64Arch = fatHeader.architectures.first(where: { $0.cpuType == .arm64 }) else {
      XCTFail("Should have arm64 architecture")
      return
    }

    // Extract the slice
    let sliceReader = try reader.slice(at: Int(arm64Arch.offset), count: Int(arm64Arch.size))

    // Parse the slice header
    let header = try MachHeader.parse(from: sliceReader)

    XCTAssertEqual(header.cpuType, .arm64, "Extracted slice should be arm64")
    XCTAssertEqual(header.fileType, .execute, "Slice should be executable")
  }

  func testSliceOffsetAlignment() throws {
    let reader = try loadBinary(at: fatBinaryPath)
    let fatHeader = try FatHeader.parse(from: reader)

    for arch in fatHeader.architectures {
      // Slice offsets should be aligned based on alignment field
      let alignment = 1 << arch.alignment
      let isAligned = Int(arch.offset) % alignment == 0

      XCTAssertTrue(
        isAligned,
        "Slice offset \(arch.offset) should be \(alignment)-byte aligned")
    }
  }

  // MARK: - MachOBinary Fat Support Tests

  func testMachOBinaryLoadsFatBinary() throws {
    // MachOBinary should automatically extract the arm64 slice
    let binary = try MachOBinary(path: fatBinaryPath)

    XCTAssertEqual(
      binary.header.cpuType, .arm64,
      "MachOBinary should extract arm64 slice by default")
  }

  func testMachOBinaryWithArchSelection() throws {
    // Test explicit architecture selection
    let binary = try MachOBinary(path: fatBinaryPath, architecture: .arm64)

    XCTAssertEqual(
      binary.header.cpuType, .arm64,
      "Should load arm64 when explicitly requested")
  }

  // MARK: - Fat Arch Structure Tests

  func testFatArchSize() throws {
    let reader = try loadBinary(at: fatBinaryPath)
    let fatHeader = try FatHeader.parse(from: reader)

    for arch in fatHeader.architectures {
      XCTAssertGreaterThan(arch.size, 0, "Slice size should be > 0")

      // Size should accommodate at least a mach header
      XCTAssertGreaterThanOrEqual(
        arch.size, UInt32(MachHeader.size64),
        "Slice should be large enough for header")
    }
  }

  func testFatArchBounds() throws {
    let reader = try loadBinary(at: fatBinaryPath)
    let fatHeader = try FatHeader.parse(from: reader)

    for arch in fatHeader.architectures {
      let end = UInt64(arch.offset) + UInt64(arch.size)
      XCTAssertLessThanOrEqual(
        Int(end), reader.size,
        "Slice should be within file bounds")
    }
  }

  // MARK: - Error Handling Tests

  func testInvalidFatMagic() throws {
    // Create data with wrong magic
    let invalidData = Data([0x00, 0x00, 0x00, 0x00] + Array(repeating: UInt8(0), count: 20))
    let reader = BinaryReader(data: invalidData)

    XCTAssertThrowsError(try FatHeader.parse(from: reader)) { error in
      guard case MachOParseError.invalidFatMagic = error else {
        XCTFail("Expected invalidFatMagic error, got \(error)")
        return
      }
    }
  }

  func testEmptyFatBinary() throws {
    // Create a fat header with 0 architectures
    var data = Data()
    // Magic: FAT_MAGIC (big-endian)
    data.append(contentsOf: [0xCA, 0xFE, 0xBA, 0xBE])
    // Number of architectures: 0
    data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])

    let reader = BinaryReader(data: data)

    XCTAssertThrowsError(try FatHeader.parse(from: reader)) { error in
      guard case MachOParseError.emptyFatBinary = error else {
        XCTFail("Expected emptyFatBinary error, got \(error)")
        return
      }
    }
  }

  func testArchitectureNotFound() throws {
    // Try to load a non-existent architecture from fat binary
    XCTAssertThrowsError(try MachOBinary(path: fatBinaryPath, architecture: .powerPC)) { error in
      guard case MachOParseError.architectureNotFound = error else {
        XCTFail("Expected architectureNotFound error, got \(error)")
        return
      }
    }
  }
}
