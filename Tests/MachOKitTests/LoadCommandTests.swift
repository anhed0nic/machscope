// LoadCommandTests.swift
// MachOKitTests
//
// Unit tests for LoadCommand parsing

import XCTest

@testable import MachOKit

final class LoadCommandTests: XCTestCase {

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

  // MARK: - Load Command Type Tests

  func testLoadCommandTypeRawValues() {
    XCTAssertEqual(LoadCommandType.segment64.rawValue, 0x19)
    XCTAssertEqual(LoadCommandType.symtab.rawValue, 0x02)
    XCTAssertEqual(LoadCommandType.dysymtab.rawValue, 0x0B)
    XCTAssertEqual(LoadCommandType.loadDylib.rawValue, 0x0C)
    XCTAssertEqual(LoadCommandType.codeSignature.rawValue, 0x1D)
    XCTAssertEqual(LoadCommandType.main.rawValue, 0x8000_0028)
  }

  func testLoadCommandTypeDescriptions() {
    XCTAssertEqual(LoadCommandType.segment64.description, "LC_SEGMENT_64")
    XCTAssertEqual(LoadCommandType.symtab.description, "LC_SYMTAB")
    XCTAssertEqual(LoadCommandType.loadDylib.description, "LC_LOAD_DYLIB")
    XCTAssertEqual(LoadCommandType.main.description, "LC_MAIN")
  }

  // MARK: - Load Command Parsing

  func testParseLoadCommands() throws {
    let reader = try loadBinary(at: simpleARM64Path)
    let header = try MachHeader.parse(from: reader)

    // Parse load commands after the header
    let commands = try LoadCommand.parseAll(
      from: reader,
      at: MachHeader.size64,
      count: Int(header.numberOfCommands),
      totalSize: Int(header.sizeOfCommands)
    )

    XCTAssertEqual(
      commands.count, Int(header.numberOfCommands),
      "Should parse all load commands")

    // Verify we have at least a segment command
    let hasSegment = commands.contains { $0.type == .segment64 }
    XCTAssertTrue(hasSegment, "Should have at least one LC_SEGMENT_64")
  }

  func testLoadCommandMinimumSize() throws {
    // Each load command must be at least 8 bytes (cmd + cmdsize)
    let reader = try loadBinary(at: simpleARM64Path)
    let header = try MachHeader.parse(from: reader)

    let commands = try LoadCommand.parseAll(
      from: reader,
      at: MachHeader.size64,
      count: Int(header.numberOfCommands),
      totalSize: Int(header.sizeOfCommands)
    )

    for command in commands {
      XCTAssertGreaterThanOrEqual(
        command.size, 8,
        "Load command size must be at least 8 bytes")
    }
  }

  func testLoadCommandAlignment() throws {
    // Load command sizes should be 8-byte aligned
    let reader = try loadBinary(at: simpleARM64Path)
    let header = try MachHeader.parse(from: reader)

    let commands = try LoadCommand.parseAll(
      from: reader,
      at: MachHeader.size64,
      count: Int(header.numberOfCommands),
      totalSize: Int(header.sizeOfCommands)
    )

    for command in commands {
      XCTAssertEqual(
        command.size % 8, 0,
        "Load command size \(command.size) should be 8-byte aligned")
    }
  }

  // MARK: - Segment Command Tests

  func testParseSegmentCommand() throws {
    let reader = try loadBinary(at: simpleARM64Path)
    let header = try MachHeader.parse(from: reader)

    let commands = try LoadCommand.parseAll(
      from: reader,
      at: MachHeader.size64,
      count: Int(header.numberOfCommands),
      totalSize: Int(header.sizeOfCommands)
    )

    // Find a segment command and verify its payload
    guard let segmentCmd = commands.first(where: { $0.type == .segment64 }),
      case .segment(let segment) = segmentCmd.payload
    else {
      XCTFail("Should have a segment command with payload")
      return
    }

    // First segment is typically __PAGEZERO or __TEXT
    XCTAssertTrue(
      segment.name == "__PAGEZERO" || segment.name == "__TEXT",
      "First segment should be __PAGEZERO or __TEXT, got \(segment.name)")
  }

  // MARK: - Invalid Load Command Tests

  func testInvalidLoadCommandSize() throws {
    // Create a header indicating 1 command, but with truncated data
    var data = Data()

    // Write valid 64-bit magic
    data.append(contentsOf: [0xCF, 0xFA, 0xED, 0xFE])
    // CPU type: ARM64
    data.append(contentsOf: withUnsafeBytes(of: Int32(0x0100_000C).littleEndian) { Data($0) })
    // CPU subtype: ALL
    data.append(contentsOf: withUnsafeBytes(of: Int32(0).littleEndian) { Data($0) })
    // File type: EXECUTE
    data.append(contentsOf: withUnsafeBytes(of: UInt32(2).littleEndian) { Data($0) })
    // Number of commands: 1
    data.append(contentsOf: withUnsafeBytes(of: UInt32(1).littleEndian) { Data($0) })
    // Size of commands: 100 (more than available)
    data.append(contentsOf: withUnsafeBytes(of: UInt32(100).littleEndian) { Data($0) })
    // Flags
    data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Data($0) })
    // Reserved
    data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Data($0) })

    // Add a malformed load command (too short)
    data.append(contentsOf: [0x19, 0x00, 0x00, 0x00])  // cmd = LC_SEGMENT_64
    // Missing cmdsize and rest

    let reader = BinaryReader(data: data)
    let header = try MachHeader.parse(from: reader)

    XCTAssertThrowsError(
      try LoadCommand.parseAll(
        from: reader,
        at: MachHeader.size64,
        count: Int(header.numberOfCommands),
        totalSize: Int(header.sizeOfCommands)
      )
    ) { error in
      // Should fail due to insufficient data
      XCTAssertTrue(error is MachOParseError, "Should throw MachOParseError")
    }
  }

  // MARK: - Unknown Load Command Tests

  func testUnknownLoadCommandType() {
    // Test that unknown load command types are handled gracefully
    let unknownType = LoadCommandType(rawValue: 0xFFFF_FFFF)
    XCTAssertNil(unknownType, "Unknown raw value should return nil")
  }
}
