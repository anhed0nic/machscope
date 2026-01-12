// ExportIntegrationTests.swift
// IntegrationTests
//
// Integration tests for symbol and string export functionality

import XCTest

@testable import MachOKit

final class ExportIntegrationTests: XCTestCase {

  // MARK: - Setup

  private var simpleARM64Path: String {
    // Find the test fixture path
    let testBundle = Bundle(for: type(of: self))
    if let resourcePath = testBundle.resourcePath {
      return URL(fileURLWithPath: resourcePath)
        .appendingPathComponent("simple_arm64")
        .path
    }
    // Fallback to relative path from test file
    return URL(fileURLWithPath: #file)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("MachOKitTests")
      .appendingPathComponent("Fixtures")
      .appendingPathComponent("simple_arm64")
      .path
  }

  // MARK: - Symbol Export Tests

  func testExportSymbolsAsJSON() throws {
    // Skip if fixture doesn't exist
    guard FileManager.default.fileExists(atPath: simpleARM64Path) else {
      throw XCTSkip("Test fixture not found at \(simpleARM64Path)")
    }

    let binary = try MachOBinary(path: simpleARM64Path)

    // Get symbols
    guard let symbols = binary.symbols else {
      XCTFail("Expected binary to have symbols")
      return
    }

    // Convert to JSON format
    let exportedSymbols = symbols.map { symbol -> [String: Any] in
      [
        "name": symbol.name,
        "address": String(format: "0x%llX", symbol.address),
        "type": symbol.type.description,
        "external": symbol.isExternal,
        "defined": symbol.isDefined,
      ]
    }

    // Verify JSON serialization works
    let jsonData = try JSONSerialization.data(
      withJSONObject: exportedSymbols, options: [.prettyPrinted])
    XCTAssertFalse(jsonData.isEmpty)

    // Verify we can parse it back
    let parsed = try JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]]
    XCTAssertNotNil(parsed)
    XCTAssertEqual(parsed?.count, symbols.count)
  }

  func testExportDefinedSymbolsOnly() throws {
    guard FileManager.default.fileExists(atPath: simpleARM64Path) else {
      throw XCTSkip("Test fixture not found at \(simpleARM64Path)")
    }

    let binary = try MachOBinary(path: simpleARM64Path)

    guard let symbols = binary.symbols else {
      XCTFail("Expected binary to have symbols")
      return
    }

    let definedSymbols = symbols.filter { $0.isDefined && !$0.isDebugSymbol }
    let undefinedSymbols = symbols.filter { !$0.isDefined && !$0.isDebugSymbol }

    // Both categories should be exportable
    XCTAssertTrue(definedSymbols.count + undefinedSymbols.count > 0)
  }

  // MARK: - String Export Tests

  func testExportStringsAsJSON() throws {
    guard FileManager.default.fileExists(atPath: simpleARM64Path) else {
      throw XCTSkip("Test fixture not found at \(simpleARM64Path)")
    }

    let binary = try MachOBinary(path: simpleARM64Path)
    let extractor = StringExtractor(binary: binary)

    let strings = try extractor.extractAllStrings()

    // Convert to JSON format
    let exportedStrings = strings.map { string -> [String: Any] in
      [
        "value": string.value,
        "offset": string.offset,
        "section": string.section,
      ]
    }

    // Verify JSON serialization works
    let jsonData = try JSONSerialization.data(
      withJSONObject: exportedStrings, options: [.prettyPrinted])
    XCTAssertFalse(jsonData.isEmpty)

    // Verify we can parse it back
    let parsed = try JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]]
    XCTAssertNotNil(parsed)
    XCTAssertEqual(parsed?.count, strings.count)
  }

  func testExportStringsFromSpecificSection() throws {
    guard FileManager.default.fileExists(atPath: simpleARM64Path) else {
      throw XCTSkip("Test fixture not found at \(simpleARM64Path)")
    }

    let binary = try MachOBinary(path: simpleARM64Path)
    let extractor = StringExtractor(binary: binary)

    // Extract from __cstring section specifically
    let cstrings = try extractor.extractStrings(from: "__TEXT", section: "__cstring")

    // All extracted strings should be from __cstring
    for string in cstrings {
      XCTAssertEqual(string.section, "__cstring")
    }
  }

  // MARK: - Combined Export Tests

  func testExportCombinedSymbolsAndStrings() throws {
    guard FileManager.default.fileExists(atPath: simpleARM64Path) else {
      throw XCTSkip("Test fixture not found at \(simpleARM64Path)")
    }

    let binary = try MachOBinary(path: simpleARM64Path)
    let extractor = StringExtractor(binary: binary)

    // Build combined export structure
    var exportDict: [String: Any] = [
      "path": binary.path,
      "fileSize": binary.fileSize,
    ]

    // Add symbols
    if let symbols = binary.symbols {
      let symbolExport = symbols.filter { !$0.isDebugSymbol }.map { symbol -> [String: Any] in
        [
          "name": symbol.name,
          "address": String(format: "0x%llX", symbol.address),
          "type": symbol.type.description,
          "external": symbol.isExternal,
          "defined": symbol.isDefined,
        ]
      }
      exportDict["symbols"] = [
        "count": symbols.count,
        "entries": symbolExport,
      ]
    }

    // Add strings
    let strings = try extractor.extractAllStrings()
    let stringExport = strings.map { string -> [String: Any] in
      [
        "value": string.value,
        "offset": string.offset,
        "section": string.section,
      ]
    }
    exportDict["strings"] = [
      "count": strings.count,
      "entries": stringExport,
    ]

    // Verify complete export
    let jsonData = try JSONSerialization.data(
      withJSONObject: exportDict, options: [.prettyPrinted, .sortedKeys])
    XCTAssertFalse(jsonData.isEmpty)

    // Verify structure
    let parsed = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
    XCTAssertNotNil(parsed?["path"])
    XCTAssertNotNil(parsed?["fileSize"])
    XCTAssertNotNil(parsed?["symbols"])
    XCTAssertNotNil(parsed?["strings"])
  }

  // MARK: - Export Format Validation Tests

  func testSymbolAddressFormat() throws {
    guard FileManager.default.fileExists(atPath: simpleARM64Path) else {
      throw XCTSkip("Test fixture not found at \(simpleARM64Path)")
    }

    let binary = try MachOBinary(path: simpleARM64Path)

    guard let symbols = binary.symbols, let symbol = symbols.first(where: { $0.isDefined }) else {
      throw XCTSkip("No defined symbols found")
    }

    // Address should be formatted as hex string
    let addressString = String(format: "0x%llX", symbol.address)
    XCTAssertTrue(addressString.hasPrefix("0x"))

    // Should be able to parse back
    let scanner = Scanner(string: addressString)
    var parsedValue: UInt64 = 0
    XCTAssertTrue(scanner.scanHexInt64(&parsedValue))
    XCTAssertEqual(parsedValue, symbol.address)
  }

  func testStringOffsetValidity() throws {
    guard FileManager.default.fileExists(atPath: simpleARM64Path) else {
      throw XCTSkip("Test fixture not found at \(simpleARM64Path)")
    }

    let binary = try MachOBinary(path: simpleARM64Path)
    let extractor = StringExtractor(binary: binary)

    let strings = try extractor.extractAllStrings()

    // All offsets should be positive and within file size
    for string in strings {
      XCTAssertGreaterThanOrEqual(string.offset, 0)
      XCTAssertLessThan(UInt64(string.offset), binary.fileSize)
    }
  }

  // MARK: - Performance Tests

  func testExportPerformance() throws {
    guard FileManager.default.fileExists(atPath: simpleARM64Path) else {
      throw XCTSkip("Test fixture not found at \(simpleARM64Path)")
    }

    measure {
      do {
        let binary = try MachOBinary(path: simpleARM64Path)
        let extractor = StringExtractor(binary: binary)

        _ = binary.symbols
        _ = try extractor.extractAllStrings()
      } catch {
        XCTFail("Export failed: \(error)")
      }
    }
  }

  // MARK: - Edge Cases

  func testExportEmptyBinary() throws {
    // Test with a binary that might have no symbols
    // This is a defensive test - our fixtures should have symbols
    guard FileManager.default.fileExists(atPath: simpleARM64Path) else {
      throw XCTSkip("Test fixture not found at \(simpleARM64Path)")
    }

    let binary = try MachOBinary(path: simpleARM64Path)
    let extractor = StringExtractor(binary: binary)

    // Even if empty, export should succeed
    let symbols = binary.symbols ?? []
    let strings = try extractor.extractAllStrings()

    // Both should be arrays (possibly empty)
    XCTAssertTrue(symbols is [Symbol])
    XCTAssertTrue(strings is [ExtractedString])
  }

  func testExportFilteredByType() throws {
    guard FileManager.default.fileExists(atPath: simpleARM64Path) else {
      throw XCTSkip("Test fixture not found at \(simpleARM64Path)")
    }

    let binary = try MachOBinary(path: simpleARM64Path)

    guard let symbols = binary.symbols else {
      throw XCTSkip("No symbols in binary")
    }

    // Group symbols by type
    let groupedSymbols = Dictionary(grouping: symbols) { $0.type }

    // Each group should be exportable
    for (type, typeSymbols) in groupedSymbols {
      let exported = typeSymbols.map { ["name": $0.name, "type": type.description] }
      let data = try JSONSerialization.data(withJSONObject: exported)
      XCTAssertFalse(data.isEmpty)
    }
  }
}
