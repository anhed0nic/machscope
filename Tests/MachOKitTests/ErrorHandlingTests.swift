// ErrorHandlingTests.swift
// MachOKitTests
//
// Unit tests for malformed binary handling and error cases

import XCTest

@testable import MachOKit

final class ErrorHandlingTests: XCTestCase {

  // MARK: - Test Fixtures Path

  private var fixturesPath: String {
    let currentFile = #filePath
    let testsDir = URL(fileURLWithPath: currentFile)
      .deletingLastPathComponent()
    return testsDir.appendingPathComponent("Fixtures").path
  }

  private var truncatedPath: String {
    fixturesPath + "/malformed/truncated"
  }

  private var invalidMagicPath: String {
    fixturesPath + "/malformed/invalid_magic"
  }

  // MARK: - File Not Found Tests

  func testFileNotFound() {
    let nonExistentPath = "/nonexistent/path/to/binary"

    XCTAssertThrowsError(try MachOBinary(path: nonExistentPath)) { error in
      guard case MachOParseError.fileNotFound(let path) = error else {
        XCTFail("Expected fileNotFound error, got \(error)")
        return
      }
      XCTAssertEqual(path, nonExistentPath)
    }
  }

  // MARK: - Invalid Magic Tests

  func testInvalidMagicNumber() throws {
    XCTAssertThrowsError(try MachOBinary(path: invalidMagicPath)) { error in
      guard case MachOParseError.invalidMagic(let found, let at) = error else {
        XCTFail("Expected invalidMagic error, got \(error)")
        return
      }
      XCTAssertEqual(at, 0, "Invalid magic should be at offset 0")
      // Our test fixture starts with 'X' characters
      XCTAssertNotEqual(found, MachOMagic.mh64.rawValue, "Magic should not match valid")
    }
  }

  // MARK: - Truncated Header Tests

  func testTruncatedHeader() throws {
    XCTAssertThrowsError(try MachOBinary(path: truncatedPath)) { error in
      switch error {
      case MachOParseError.insufficientData(let offset, let needed, let available):
        // Truncated file is only 16 bytes, header needs 32
        XCTAssertLessThan(
          available, needed,
          "Available bytes should be less than needed")
        _ = offset  // Offset may vary

      case MachOParseError.truncatedHeader(let offset, let needed, let available):
        XCTAssertLessThan(available, needed)
        _ = offset

      default:
        XCTFail("Expected insufficientData or truncatedHeader error, got \(error)")
      }
    }
  }

  // MARK: - Empty File Tests

  func testEmptyFile() throws {
    // Create temporary empty file
    let tempDir = FileManager.default.temporaryDirectory
    let emptyPath = tempDir.appendingPathComponent("empty_test_\(UUID().uuidString)").path

    FileManager.default.createFile(atPath: emptyPath, contents: Data(), attributes: nil)
    defer { try? FileManager.default.removeItem(atPath: emptyPath) }

    XCTAssertThrowsError(try MachOBinary(path: emptyPath)) { error in
      guard case MachOParseError.insufficientData = error else {
        XCTFail("Expected insufficientData error for empty file, got \(error)")
        return
      }
    }
  }

  // MARK: - Binary Reader Bounds Tests

  func testBinaryReaderOutOfBounds() throws {
    let smallData = Data([0x01, 0x02, 0x03, 0x04])
    let reader = BinaryReader(data: smallData)

    // Reading within bounds should work
    XCTAssertNoThrow(try reader.readUInt32(at: 0))

    // Reading beyond bounds should throw
    XCTAssertThrowsError(try reader.readUInt32(at: 4)) { error in
      guard case MachOParseError.insufficientData(_, let needed, let available) = error else {
        XCTFail("Expected insufficientData error, got \(error)")
        return
      }
      XCTAssertEqual(needed, 4)
      XCTAssertEqual(available, 0)
    }
  }

  func testBinaryReaderNegativeOffset() throws {
    let data = Data([0x01, 0x02, 0x03, 0x04])
    let reader = BinaryReader(data: data)

    XCTAssertThrowsError(try reader.readUInt32(at: -1)) { error in
      guard case MachOParseError.insufficientData = error else {
        XCTFail("Expected insufficientData error, got \(error)")
        return
      }
    }
  }

  // MARK: - Load Command Validation Tests

  func testLoadCommandSizeTooSmall() throws {
    var data = Data()

    // Write valid 64-bit header
    data.append(contentsOf: [0xCF, 0xFA, 0xED, 0xFE])  // Magic
    data.append(contentsOf: withUnsafeBytes(of: Int32(0x0100_000C).littleEndian) { Data($0) })  // ARM64
    data.append(contentsOf: withUnsafeBytes(of: Int32(0).littleEndian) { Data($0) })  // Subtype
    data.append(contentsOf: withUnsafeBytes(of: UInt32(2).littleEndian) { Data($0) })  // EXECUTE
    data.append(contentsOf: withUnsafeBytes(of: UInt32(1).littleEndian) { Data($0) })  // 1 command
    data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })  // Size
    data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Data($0) })  // Flags
    data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Data($0) })  // Reserved

    // Add load command with size 4 (less than minimum 8)
    data.append(contentsOf: [0x19, 0x00, 0x00, 0x00])  // LC_SEGMENT_64
    data.append(contentsOf: [0x04, 0x00, 0x00, 0x00])  // Size = 4 (invalid)
    // Pad to make it "complete" per header
    data.append(contentsOf: Array(repeating: UInt8(0), count: 8))

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
      // Should fail due to invalid command size
      XCTAssertTrue(error is MachOParseError, "Should throw MachOParseError")
    }
  }

  // MARK: - Error Description Tests

  func testErrorDescriptions() {
    let errors: [MachOParseError] = [
      .invalidMagic(found: 0x1234_5678, at: 0),
      .truncatedHeader(offset: 0, needed: 32, available: 16),
      .unsupportedCPUType(999),
      .loadCommandSizeMismatch(expected: 100, actual: 50),
      .segmentOutOfBounds(name: "__TEXT", offset: 1000, size: 500),
      .sectionOutOfBounds(name: "__text", offset: 1000, size: 500),
      .invalidFatMagic(found: 0xDEAD_BEEF),
      .emptyFatBinary,
      .insufficientData(offset: 100, needed: 32, available: 16),
      .fileNotFound(path: "/some/path"),
    ]

    for error in errors {
      let description = error.description
      XCTAssertFalse(description.isEmpty, "Error should have description")
      XCTAssertGreaterThan(
        description.count, 10,
        "Error description should be meaningful")
    }
  }

  func testErrorIsDescriptive() {
    let error = MachOParseError.insufficientData(offset: 100, needed: 32, available: 16)
    let description = error.description

    XCTAssertTrue(description.contains("100"), "Should mention offset")
    XCTAssertTrue(description.contains("32"), "Should mention needed bytes")
    XCTAssertTrue(description.contains("16"), "Should mention available bytes")
  }

  // MARK: - Recovery Tests

  func testPartialParsingOnError() throws {
    // Even if later parsing fails, earlier results should be valid
    let reader = try loadBinary(at: truncatedPath)

    // Should be able to read whatever is available
    if reader.size >= 4 {
      let magic = try reader.readUInt32(at: 0)
      // Magic might be valid even in truncated file
      XCTAssertNotEqual(magic, 0, "Should read some data")
    }
  }

  // MARK: - Memory Mapped File Tests

  func testMemoryMappedFileNotFound() {
    let nonExistent = "/nonexistent/file/path"

    XCTAssertThrowsError(try MemoryMappedFile(path: nonExistent)) { error in
      guard case MachOParseError.fileNotFound(let path) = error else {
        XCTFail("Expected fileNotFound error, got \(error)")
        return
      }
      XCTAssertEqual(path, nonExistent)
    }
  }

  // MARK: - Segment Bounds Tests

  func testSegmentOutOfFileBounds() throws {
    // This tests that segment validation catches out-of-bounds segments
    // In practice, we rely on the fixture having valid segments

    var data = Data()

    // Valid header
    data.append(contentsOf: [0xCF, 0xFA, 0xED, 0xFE])  // Magic
    data.append(contentsOf: withUnsafeBytes(of: Int32(0x0100_000C).littleEndian) { Data($0) })
    data.append(contentsOf: withUnsafeBytes(of: Int32(0).littleEndian) { Data($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt32(2).littleEndian) { Data($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt32(1).littleEndian) { Data($0) })  // 1 command
    data.append(contentsOf: withUnsafeBytes(of: UInt32(72).littleEndian) { Data($0) })  // Size
    data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Data($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Data($0) })

    // LC_SEGMENT_64 command
    data.append(contentsOf: withUnsafeBytes(of: UInt32(0x19).littleEndian) { Data($0) })  // cmd
    data.append(contentsOf: withUnsafeBytes(of: UInt32(72).littleEndian) { Data($0) })  // cmdsize

    // Segment name (16 bytes)
    var name = "__TEXT".data(using: .ascii)!
    name.append(contentsOf: Array(repeating: UInt8(0), count: 16 - name.count))
    data.append(name)

    // vmaddr
    data.append(contentsOf: withUnsafeBytes(of: UInt64(0x1_0000_0000).littleEndian) { Data($0) })
    // vmsize
    data.append(contentsOf: withUnsafeBytes(of: UInt64(0x10000).littleEndian) { Data($0) })
    // fileoff - intentionally out of bounds
    data.append(contentsOf: withUnsafeBytes(of: UInt64(0xFFFF_FFFF).littleEndian) { Data($0) })
    // filesize
    data.append(contentsOf: withUnsafeBytes(of: UInt64(0x10000).littleEndian) { Data($0) })
    // maxprot
    data.append(contentsOf: withUnsafeBytes(of: Int32(7).littleEndian) { Data($0) })
    // initprot
    data.append(contentsOf: withUnsafeBytes(of: Int32(5).littleEndian) { Data($0) })
    // nsects
    data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Data($0) })
    // flags
    data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Data($0) })

    let reader = BinaryReader(data: data)
    let header = try MachHeader.parse(from: reader)

    // Parsing should succeed but validation might catch the issue
    let commands = try LoadCommand.parseAll(
      from: reader,
      at: MachHeader.size64,
      count: Int(header.numberOfCommands),
      totalSize: Int(header.sizeOfCommands)
    )

    // The command parses, but if we try to read segment data, it should fail
    guard case .segment(let segment) = commands.first?.payload else {
      XCTFail("Should have segment payload")
      return
    }

    // Segment fileOffset is way beyond file size
    XCTAssertGreaterThan(
      segment.fileOffset, UInt64(reader.size),
      "Segment offset should be beyond file")
  }
}
