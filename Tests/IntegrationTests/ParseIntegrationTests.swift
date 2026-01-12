// ParseIntegrationTests.swift
// IntegrationTests
//
// Integration tests for Mach-O parsing using test fixtures

import XCTest

@testable import MachOKit

final class ParseIntegrationTests: XCTestCase {

  // MARK: - Test Fixtures Path

  private var fixturesPath: String {
    // Navigate from IntegrationTests to MachOKitTests/Fixtures
    let currentFile = #filePath
    let testsDir = URL(fileURLWithPath: currentFile)
      .deletingLastPathComponent()  // Remove filename
      .deletingLastPathComponent()  // Remove IntegrationTests
    return testsDir.appendingPathComponent("MachOKitTests/Fixtures").path
  }

  private var simpleARM64Path: String {
    fixturesPath + "/simple_arm64"
  }

  private var fatBinaryPath: String {
    fixturesPath + "/fat_binary"
  }

  // MARK: - Simple ARM64 Binary Tests

  func testParseSimpleARM64Binary() throws {
    let binary = try MachOBinary(path: simpleARM64Path)

    // Verify basic structure
    XCTAssertEqual(binary.path, simpleARM64Path)
    XCTAssertEqual(binary.header.cpuType, .arm64)
    XCTAssertEqual(binary.header.fileType, .execute)
  }

  func testSimpleARM64HasExpectedSegments() throws {
    let binary = try MachOBinary(path: simpleARM64Path)

    let segmentNames = Set(binary.segments.map { $0.name })

    // Typical executable segments
    XCTAssertTrue(segmentNames.contains("__TEXT"), "Should have __TEXT segment")
    XCTAssertTrue(segmentNames.contains("__LINKEDIT"), "Should have __LINKEDIT segment")

    // May or may not have these depending on binary
    // __PAGEZERO, __DATA, __DATA_CONST are common but not required
  }

  func testSimpleARM64HasTextSection() throws {
    let binary = try MachOBinary(path: simpleARM64Path)

    guard let textSegment = binary.segments.first(where: { $0.name == "__TEXT" }) else {
      XCTFail("Should have __TEXT segment")
      return
    }

    let hasTextSection = textSegment.sections.contains { $0.name == "__text" }
    XCTAssertTrue(hasTextSection, "__TEXT segment should have __text section")
  }

  func testSimpleARM64HasMainSymbol() throws {
    let binary = try MachOBinary(path: simpleARM64Path)

    let mainSymbol = binary.symbol(named: "_main")
    XCTAssertNotNil(mainSymbol, "Executable should have _main symbol")

    if let main = mainSymbol {
      XCTAssertTrue(main.isDefined, "_main should be defined")
      XCTAssertTrue(main.isExternal, "_main should be external")
      XCTAssertGreaterThan(main.address, 0, "_main should have valid address")
    }
  }

  // MARK: - Fat Binary Tests

  func testParseFatBinary() throws {
    let binary = try MachOBinary(path: fatBinaryPath)

    // Should extract arm64 slice by default
    XCTAssertEqual(binary.header.cpuType, .arm64)
    XCTAssertEqual(binary.header.fileType, .execute)
  }

  func testFatBinaryStructure() throws {
    let binary = try MachOBinary(path: fatBinaryPath)

    // Fat binary arm64 slice should have same structure as simple binary
    XCTAssertGreaterThan(binary.segments.count, 0)
    XCTAssertNotNil(binary.symbol(named: "_main"))
  }

  func testFatBinaryListArchitectures() throws {
    let reader = try loadBinary(at: fatBinaryPath)
    let fatHeader = try FatHeader.parse(from: reader)

    XCTAssertEqual(
      fatHeader.architectures.count, 2,
      "Test fat binary should have 2 architectures")

    let cpuTypes = Set(fatHeader.architectures.map { $0.cpuType })
    XCTAssertTrue(cpuTypes.contains(.arm64), "Should have arm64")
    XCTAssertTrue(cpuTypes.contains(.x86_64), "Should have x86_64")
  }

  // MARK: - Load Command Tests

  func testLoadCommandsAreParsed() throws {
    let binary = try MachOBinary(path: simpleARM64Path)

    XCTAssertGreaterThan(
      binary.loadCommands.count, 0,
      "Should have load commands")

    // Should have segment commands
    let segmentCommands = binary.loadCommands.filter { $0.type == .segment64 }
    XCTAssertGreaterThan(
      segmentCommands.count, 0,
      "Should have segment load commands")
  }

  func testSymtabLoadCommand() throws {
    let binary = try MachOBinary(path: simpleARM64Path)

    let symtabCommands = binary.loadCommands.filter { $0.type == .symtab }
    XCTAssertEqual(symtabCommands.count, 1, "Should have exactly one LC_SYMTAB")

    guard case .symtab(let symtab) = symtabCommands.first?.payload else {
      XCTFail("Symtab command should have symtab payload")
      return
    }

    XCTAssertGreaterThan(symtab.numberOfSymbols, 0, "Should have symbols")
  }

  // MARK: - Memory Access Tests

  func testSegmentDataAccess() throws {
    let binary = try MachOBinary(path: simpleARM64Path)

    guard let textSegment = binary.segments.first(where: { $0.name == "__TEXT" }),
      let textSection = textSegment.sections.first(where: { $0.name == "__text" })
    else {
      XCTFail("Should have __TEXT.__text")
      return
    }

    // Should be able to read code bytes
    let codeData = try binary.readSectionData(textSection)
    XCTAssertGreaterThan(codeData.count, 0, "Should have code bytes")

    // First instruction should be valid ARM64 (4 bytes)
    XCTAssertGreaterThanOrEqual(codeData.count, 4, "Should have at least one instruction")
  }

  // MARK: - Symbol Resolution Tests

  func testSymbolResolutionByAddress() throws {
    let binary = try MachOBinary(path: simpleARM64Path)

    guard let main = binary.symbol(named: "_main") else {
      XCTFail("Should have _main")
      return
    }

    // Look up by address
    let found = binary.symbol(at: main.address)
    XCTAssertNotNil(found)
    XCTAssertEqual(found?.name, "_main")
  }

  func testSymbolsInTextSegment() throws {
    let binary = try MachOBinary(path: simpleARM64Path)

    guard let textSegment = binary.segments.first(where: { $0.name == "__TEXT" }),
      let symbols = binary.symbols
    else {
      XCTFail("Should have __TEXT and symbols")
      return
    }

    // Find symbols within __TEXT
    let textSymbols = symbols.filter { symbol in
      symbol.isDefined && textSegment.contains(address: symbol.address)
    }

    XCTAssertGreaterThan(
      textSymbols.count, 0,
      "Should have symbols in __TEXT segment")
  }

  // MARK: - Binary Properties Tests

  func testBinaryFileSize() throws {
    let binary = try MachOBinary(path: simpleARM64Path)

    XCTAssertGreaterThan(binary.fileSize, 0)

    // File size should be reasonable for test binary (< 1MB)
    XCTAssertLessThan(binary.fileSize, 1024 * 1024)
  }

  func testBinaryMemoryMappingDecision() throws {
    let binary = try MachOBinary(path: simpleARM64Path)

    // Small test binary should not use memory mapping
    XCTAssertFalse(
      binary.isMemoryMapped,
      "Small binary should not use memory mapping")
  }

  // MARK: - Round-Trip Tests

  func testHeaderFieldsMatchExpected() throws {
    let binary = try MachOBinary(path: simpleARM64Path)

    // Verify header matches raw file
    let reader = try loadBinary(at: simpleARM64Path)
    let rawMagic = try reader.readUInt32(at: 0)

    XCTAssertEqual(binary.header.magic, rawMagic)
  }

  // MARK: - Multiple File Tests

  func testParseMultipleFiles() throws {
    // Parse both test fixtures in sequence
    let binary1 = try MachOBinary(path: simpleARM64Path)
    let binary2 = try MachOBinary(path: fatBinaryPath)

    // Both should be valid
    XCTAssertEqual(binary1.header.cpuType, .arm64)
    XCTAssertEqual(binary2.header.cpuType, .arm64)

    // Both should have _main
    XCTAssertNotNil(binary1.symbol(named: "_main"))
    XCTAssertNotNil(binary2.symbol(named: "_main"))
  }
}
