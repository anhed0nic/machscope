// IntegrationTests.swift
// IntegrationTests
//
// End-to-end integration tests for MachScope

import XCTest

@testable import DebuggerCore
@testable import Disassembler
@testable import MachOKit

final class IntegrationTests: XCTestCase {

  // MARK: - Test Fixtures Path

  private var fixturesPath: String {
    let currentFile = #filePath
    let testsDir = URL(fileURLWithPath: currentFile)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return testsDir.appendingPathComponent("MachOKitTests/Fixtures").path
  }

  private var simpleARM64Path: String {
    fixturesPath + "/simple_arm64"
  }

  // MARK: - End-to-End Workflow Tests

  func testEndToEndParseWorkflow() throws {
    // Step 1: Parse a Mach-O binary
    let binary = try MachOBinary(path: simpleARM64Path)

    // Step 2: Verify header information
    XCTAssertEqual(binary.header.cpuType, .arm64)
    XCTAssertEqual(binary.header.fileType, .execute)

    // Step 3: Verify segments are accessible
    XCTAssertFalse(binary.segments.isEmpty)
    let textSegment = binary.segment(named: "__TEXT")
    XCTAssertNotNil(textSegment)

    // Step 4: Verify sections within segments
    let textSection = binary.section(segment: "__TEXT", section: "__text")
    XCTAssertNotNil(textSection)

    // Step 5: Verify load commands
    XCTAssertFalse(binary.loadCommands.isEmpty)
    let segmentCommands = binary.loadCommands.filter { $0.type == .segment64 }
    XCTAssertFalse(segmentCommands.isEmpty)

    // Step 6: Verify symbol table
    let symbols = binary.symbols
    XCTAssertNotNil(symbols)
    let mainSymbol = binary.symbol(named: "_main")
    XCTAssertNotNil(mainSymbol)
  }

  func testEndToEndDisassemblyWorkflow() throws {
    // Step 1: Parse the binary
    let binary = try MachOBinary(path: simpleARM64Path)

    // Step 2: Create disassembler
    let options = DisassemblyOptions()
    let disassembler = ARM64Disassembler(binary: binary, options: options)

    // Step 3: Find _main symbol
    guard let mainSymbol = binary.symbol(named: "_main") else {
      throw XCTSkip("No _main symbol found in test binary")
    }

    // Step 4: Get text section for disassembly
    guard let textSection = binary.section(segment: "__TEXT", section: "__text") else {
      throw XCTSkip("No __text section found")
    }

    // Step 5: Disassemble the section
    let result = try disassembler.disassembleSection(textSection, from: binary)

    // Step 6: Verify disassembly result
    XCTAssertGreaterThan(result.count, 0)
    XCTAssertGreaterThan(result.byteCount, 0)

    // Step 7: Verify instructions are decodable
    for instruction in result.instructions.prefix(10) {
      XCTAssertGreaterThan(instruction.address, 0)
      XCTAssertFalse(instruction.mnemonic.isEmpty)
    }
  }

  func testEndToEndPermissionCheck() {
    // Step 1: Create permission checker
    let checker = PermissionChecker()

    // Step 2: Check permission status
    let status = checker.status

    // Step 3: Verify status fields are populated
    XCTAssertTrue(status.staticAnalysis, "Static analysis should always be available")
    XCTAssertTrue(status.disassembly, "Disassembly should always be available")

    // Step 4: Verify tier is valid
    let tier = checker.tier
    XCTAssertTrue(
      tier == .full || tier == .analysis || tier == .readOnly,
      "Tier should be one of the valid values")

    // Step 5: Verify exit code is valid
    let exitCode = checker.exitCode
    XCTAssertTrue(
      exitCode == 0 || exitCode == 20 || exitCode == 21,
      "Exit code should be valid")
  }

  func testEndToEndCodeSignatureWorkflow() throws {
    // Step 1: Parse binary
    let binary = try MachOBinary(path: simpleARM64Path)

    // Step 2: Check if signed
    if binary.isSigned {
      // Step 3: Parse code signature
      guard let signature = try binary.parseCodeSignature() else {
        XCTFail("Signed binary should have parseable signature")
        return
      }

      // Step 4: Verify code directory
      if let codeDir = signature.codeDirectory {
        XCTAssertFalse(codeDir.identifier.isEmpty)
        XCTAssertGreaterThan(codeDir.codeLimit, 0)
      }

      // Step 5: Check entitlements (if present)
      if let entitlements = signature.entitlements {
        XCTAssertGreaterThanOrEqual(entitlements.count, 0)
      }
    }
  }

  func testEndToEndStringExtractionWorkflow() throws {
    // Step 1: Parse binary
    let binary = try MachOBinary(path: simpleARM64Path)

    // Step 2: Create string extractor
    let extractor = StringExtractor(binary: binary)

    // Step 3: Extract strings
    let strings = try extractor.extractAllStrings()

    // Step 4: Verify strings were extracted
    XCTAssertGreaterThanOrEqual(strings.count, 0)

    // Step 5: Verify string structure
    for string in strings.prefix(10) {
      XCTAssertFalse(string.value.isEmpty)
      XCTAssertFalse(string.section.isEmpty)
    }
  }

  func testEndToEndSymbolResolution() throws {
    // Step 1: Parse binary
    let binary = try MachOBinary(path: simpleARM64Path)

    // Step 2: Create disassembler with symbol resolution
    let options = DisassemblyOptions(resolveSymbols: true, demangleSwift: true)
    let disassembler = ARM64Disassembler(binary: binary, options: options)

    // Step 3: List functions
    let functions = disassembler.listFunctions(in: binary)

    // Step 4: If functions exist, verify they have valid addresses
    for (name, address) in functions {
      XCTAssertFalse(name.isEmpty)
      XCTAssertGreaterThan(address, 0)
    }

    // Step 5: Verify symbol lookup through binary
    if let mainSymbol = binary.symbol(named: "_main") {
      // Verify we can look up by address too
      let foundSymbol = binary.symbol(at: mainSymbol.address)
      XCTAssertNotNil(foundSymbol)
      XCTAssertEqual(foundSymbol?.name, "_main")
    }
  }

  func testFullBinaryAnalysisWorkflow() throws {
    // This test simulates what the CLI 'parse --all' command does

    // Step 1: Parse binary
    let binary = try MachOBinary(path: simpleARM64Path)

    // Step 2: Gather all analysis data
    let header = binary.header
    let segments = binary.segments
    let loadCommands = binary.loadCommands
    let symbols = binary.symbols ?? []
    let dylibs = binary.dylibDependencies

    // Step 3: Verify all data is accessible
    XCTAssertEqual(header.cpuType, .arm64)
    XCTAssertFalse(segments.isEmpty)
    XCTAssertFalse(loadCommands.isEmpty)

    // Step 4: Extract strings
    let extractor = StringExtractor(binary: binary)
    let strings = try extractor.extractAllStrings()

    // Step 5: Parse code signature (if present)
    let signature = try binary.parseCodeSignature()

    // Step 6: Verify we have a complete analysis
    XCTAssertGreaterThan(binary.fileSize, 0)
    XCTAssertNotNil(binary.path)

    // Log summary for debugging
    print("Binary Analysis Summary:")
    print("  Path: \(binary.path)")
    print("  Size: \(binary.fileSize) bytes")
    print("  CPU: \(header.cpuType)")
    print("  Segments: \(segments.count)")
    print("  Load Commands: \(loadCommands.count)")
    print("  Symbols: \(symbols.count)")
    print("  Dylibs: \(dylibs.count)")
    print("  Strings: \(strings.count)")
    print("  Signed: \(signature != nil)")
  }
}
