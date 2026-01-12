// SymbolTests.swift
// MachOKitTests
//
// Unit tests for Symbol table parsing

import XCTest

@testable import MachOKit

final class SymbolTests: XCTestCase {

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

  // MARK: - Symbol Table Loading Tests

  func testLoadSymbolTable() throws {
    let binary = try MachOBinary(path: simpleARM64Path)

    // Symbols are lazy loaded
    let symbols = binary.symbols
    XCTAssertNotNil(symbols, "Should load symbol table")
  }

  func testSymbolTableHasSymbols() throws {
    let binary = try MachOBinary(path: simpleARM64Path)

    guard let symbols = binary.symbols else {
      XCTFail("Should have symbols")
      return
    }

    XCTAssertGreaterThan(symbols.count, 0, "Should have at least one symbol")
  }

  func testMainSymbolExists() throws {
    let binary = try MachOBinary(path: simpleARM64Path)

    guard let symbols = binary.symbols else {
      XCTFail("Should have symbols")
      return
    }

    // Simple executables should have _main
    let hasMain = symbols.contains { $0.name == "_main" }
    XCTAssertTrue(hasMain, "Executable should have _main symbol")
  }

  // MARK: - Symbol Properties Tests

  func testSymbolAddress() throws {
    let binary = try MachOBinary(path: simpleARM64Path)

    guard let symbols = binary.symbols,
      let main = symbols.first(where: { $0.name == "_main" })
    else {
      XCTFail("Should have _main symbol")
      return
    }

    // _main should have a valid address in __TEXT
    XCTAssertGreaterThan(main.address, 0, "_main should have non-zero address")

    // Verify address is in __TEXT segment
    if let textSegment = binary.segments.first(where: { $0.name == "__TEXT" }) {
      XCTAssertTrue(
        textSegment.contains(address: main.address),
        "_main should be in __TEXT segment")
    }
  }

  func testSymbolType() throws {
    let binary = try MachOBinary(path: simpleARM64Path)

    guard let symbols = binary.symbols,
      let main = symbols.first(where: { $0.name == "_main" })
    else {
      XCTFail("Should have _main symbol")
      return
    }

    // _main should be a defined section symbol
    XCTAssertEqual(main.type, .section, "_main should be a section symbol")
    XCTAssertTrue(main.isDefined, "_main should be defined")
  }

  func testExternalSymbol() throws {
    let binary = try MachOBinary(path: simpleARM64Path)

    guard let symbols = binary.symbols,
      let main = symbols.first(where: { $0.name == "_main" })
    else {
      XCTFail("Should have _main symbol")
      return
    }

    // _main is typically external (visible)
    XCTAssertTrue(main.isExternal, "_main should be external")
  }

  // MARK: - Symbol Type Enum Tests

  func testSymbolTypeValues() {
    XCTAssertEqual(SymbolType.undefined.rawValue, 0x00)
    XCTAssertEqual(SymbolType.absolute.rawValue, 0x02)
    XCTAssertEqual(SymbolType.section.rawValue, 0x0E)
    XCTAssertEqual(SymbolType.prebound.rawValue, 0x0C)
    XCTAssertEqual(SymbolType.indirect.rawValue, 0x0A)
  }

  func testSymbolTypeDescription() {
    XCTAssertEqual(SymbolType.undefined.description, "U")
    XCTAssertEqual(SymbolType.absolute.description, "A")
    XCTAssertEqual(SymbolType.section.description, "S")
  }

  // MARK: - Symbol Lookup Tests

  func testFindSymbolByName() throws {
    let binary = try MachOBinary(path: simpleARM64Path)

    let main = binary.symbol(named: "_main")
    XCTAssertNotNil(main, "Should find _main by name")

    let nonExistent = binary.symbol(named: "_nonexistent_function")
    XCTAssertNil(nonExistent, "Should not find non-existent symbol")
  }

  func testFindSymbolByAddress() throws {
    let binary = try MachOBinary(path: simpleARM64Path)

    guard let main = binary.symbol(named: "_main") else {
      XCTFail("Should have _main symbol")
      return
    }

    let found = binary.symbol(at: main.address)
    XCTAssertNotNil(found, "Should find symbol at _main address")
    XCTAssertEqual(found?.name, "_main", "Should find _main by its address")
  }

  // MARK: - String Table Tests

  func testStringTableLoaded() throws {
    let binary = try MachOBinary(path: simpleARM64Path)

    guard let symbols = binary.symbols else {
      XCTFail("Should have symbols")
      return
    }

    // All symbols should have non-empty names (from string table)
    for symbol in symbols {
      XCTAssertFalse(symbol.name.isEmpty, "Symbol should have a name")
    }
  }

  func testSymbolNameDeduplication() throws {
    // This tests internal implementation - string table should not duplicate strings
    let binary = try MachOBinary(path: simpleARM64Path)

    guard let symbols = binary.symbols else {
      XCTFail("Should have symbols")
      return
    }

    // Group by name to find duplicates
    let grouped = Dictionary(grouping: symbols, by: { $0.name })
    let duplicates = grouped.filter { $0.value.count > 1 }

    // It's OK to have symbols with same name (different sections),
    // but they should have different properties
    for (name, syms) in duplicates {
      let uniqueAddresses = Set(syms.map { $0.address })
      if uniqueAddresses.count == 1 {
        XCTFail("Duplicate symbols '\(name)' at same address may indicate issue")
      }
    }
  }

  // MARK: - Symbol Sorting Tests

  func testSymbolsSortedByAddress() throws {
    let binary = try MachOBinary(path: simpleARM64Path)

    guard let symbols = binary.symbols else {
      XCTFail("Should have symbols")
      return
    }

    // Get defined symbols (with addresses)
    let defined = symbols.filter { $0.isDefined && $0.address > 0 }
    let sorted = defined.sorted { $0.address < $1.address }

    XCTAssertEqual(defined, sorted, "Defined symbols should be sorted by address")
  }

  // MARK: - Symbol Filtering Tests

  func testFilterExternalSymbols() throws {
    let binary = try MachOBinary(path: simpleARM64Path)

    guard let symbols = binary.symbols else {
      XCTFail("Should have symbols")
      return
    }

    let external = symbols.filter { $0.isExternal }
    XCTAssertGreaterThan(external.count, 0, "Should have external symbols")

    let local = symbols.filter { !$0.isExternal && !$0.isPrivateExternal }
    // Locals may or may not exist depending on strip level
    _ = local
  }

  func testFilterDefinedSymbols() throws {
    let binary = try MachOBinary(path: simpleARM64Path)

    guard let symbols = binary.symbols else {
      XCTFail("Should have symbols")
      return
    }

    let defined = symbols.filter { $0.isDefined }
    let undefined = symbols.filter { !$0.isDefined }

    // Executables typically have both
    XCTAssertGreaterThan(defined.count, 0, "Should have defined symbols")
    // May or may not have undefined depending on linking
    _ = undefined
  }
}
