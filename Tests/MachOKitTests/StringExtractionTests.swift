// StringExtractionTests.swift
// MachOKitTests
//
// Unit tests for string extraction from binary sections

import XCTest

@testable import MachOKit

final class StringExtractionTests: XCTestCase {

  // MARK: - Setup

  private var fixtureURL: URL {
    // Find the test fixture path
    let testBundle = Bundle(for: type(of: self))
    if let resourcePath = testBundle.resourcePath {
      return URL(fileURLWithPath: resourcePath)
        .appendingPathComponent("simple_arm64")
    }
    // Fallback to relative path from test file
    return URL(fileURLWithPath: #file)
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures")
      .appendingPathComponent("simple_arm64")
  }

  // MARK: - CString Extraction Tests

  func testExtractCStringsFromSection() throws {
    // Create test data with null-terminated strings
    let testStrings = ["Hello", "World", "Test"]
    var data = Data()
    for string in testStrings {
      data.append(string.data(using: .utf8)!)
      data.append(0)  // null terminator
    }

    let reader = BinaryReader(data: data)
    let extractor = StringExtractor(reader: reader)

    let strings = extractor.extractCStrings(at: 0, size: data.count)

    XCTAssertEqual(strings.count, 3)
    XCTAssertEqual(strings[0].value, "Hello")
    XCTAssertEqual(strings[1].value, "World")
    XCTAssertEqual(strings[2].value, "Test")
  }

  func testExtractCStringsWithOffsets() throws {
    let testStrings = ["first", "second"]
    var data = Data()
    for string in testStrings {
      data.append(string.data(using: .utf8)!)
      data.append(0)
    }

    let reader = BinaryReader(data: data)
    let extractor = StringExtractor(reader: reader)

    let strings = extractor.extractCStrings(at: 0, size: data.count)

    XCTAssertEqual(strings[0].offset, 0)
    XCTAssertEqual(strings[1].offset, 6)  // "first" + null = 6 bytes
  }

  func testExtractCStringsSkipsEmpty() throws {
    // Data with consecutive null bytes (empty strings)
    var data = Data()
    data.append("Hello".data(using: .utf8)!)
    data.append(0)
    data.append(0)  // Empty string
    data.append(0)  // Another empty
    data.append("World".data(using: .utf8)!)
    data.append(0)

    let reader = BinaryReader(data: data)
    let extractor = StringExtractor(reader: reader)

    let strings = extractor.extractCStrings(at: 0, size: data.count)

    // Should skip empty strings
    XCTAssertEqual(strings.count, 2)
    XCTAssertEqual(strings[0].value, "Hello")
    XCTAssertEqual(strings[1].value, "World")
  }

  func testExtractCStringsMinimumLength() throws {
    var data = Data()
    data.append("A".data(using: .utf8)!)  // 1 char
    data.append(0)
    data.append("BB".data(using: .utf8)!)  // 2 chars
    data.append(0)
    data.append("CCCC".data(using: .utf8)!)  // 4 chars
    data.append(0)

    let reader = BinaryReader(data: data)
    let extractor = StringExtractor(reader: reader)

    // With minimum length of 3
    let strings = extractor.extractCStrings(at: 0, size: data.count, minimumLength: 3)

    XCTAssertEqual(strings.count, 1)
    XCTAssertEqual(strings[0].value, "CCCC")
  }

  func testExtractCStringsHandlesNonPrintable() throws {
    var data = Data()
    // String with non-printable characters
    data.append([0x48, 0x65, 0x6C, 0x01, 0x6C, 0x6F, 0x00] as [UInt8], count: 7)
    // Valid string
    data.append("Valid".data(using: .utf8)!)
    data.append(0)

    let reader = BinaryReader(data: data)
    let extractor = StringExtractor(reader: reader)

    // By default should filter strings with non-printable chars
    let strings = extractor.extractCStrings(at: 0, size: data.count)

    XCTAssertEqual(strings.count, 1)
    XCTAssertEqual(strings[0].value, "Valid")
  }

  // MARK: - Section Detection Tests

  func testStringContainingSectionTypes() {
    XCTAssertTrue(SectionType.cstringLiterals.canContainStrings)
    XCTAssertTrue(SectionType.fourByteLiterals.canContainStrings)
    XCTAssertTrue(SectionType.eightByteLiterals.canContainStrings)
    XCTAssertTrue(SectionType.sixteenByteLiterals.canContainStrings)
    XCTAssertFalse(SectionType.symbolStubs.canContainStrings)
    XCTAssertFalse(SectionType.zeroFill.canContainStrings)
  }

  // MARK: - Extracted String Model Tests

  func testExtractedStringEquatable() {
    let string1 = ExtractedString(value: "test", offset: 0, section: "__cstring")
    let string2 = ExtractedString(value: "test", offset: 0, section: "__cstring")
    let string3 = ExtractedString(value: "other", offset: 0, section: "__cstring")

    XCTAssertEqual(string1, string2)
    XCTAssertNotEqual(string1, string3)
  }

  func testExtractedStringCodable() throws {
    let string = ExtractedString(value: "test", offset: 100, section: "__cstring")

    let encoder = JSONEncoder()
    let data = try encoder.encode(string)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(ExtractedString.self, from: data)

    XCTAssertEqual(decoded.value, "test")
    XCTAssertEqual(decoded.offset, 100)
    XCTAssertEqual(decoded.section, "__cstring")
  }

  // MARK: - Unicode Handling Tests

  func testExtractCStringsHandlesUTF8() throws {
    var data = Data()
    data.append("Caf\u{00E9}".data(using: .utf8)!)  // "Café" with UTF-8 encoding
    data.append(0)
    data.append("Normal".data(using: .utf8)!)
    data.append(0)

    let reader = BinaryReader(data: data)
    let extractor = StringExtractor(reader: reader)

    let strings = extractor.extractCStrings(at: 0, size: data.count)

    XCTAssertEqual(strings.count, 2)
    XCTAssertEqual(strings[0].value, "Caf\u{00E9}")
    XCTAssertEqual(strings[1].value, "Normal")
  }

  // MARK: - Edge Case Tests

  func testExtractCStringsEmptySection() throws {
    let data = Data()
    let reader = BinaryReader(data: data)
    let extractor = StringExtractor(reader: reader)

    let strings = extractor.extractCStrings(at: 0, size: 0)

    XCTAssertTrue(strings.isEmpty)
  }

  func testExtractCStringsNoNullTerminator() throws {
    // Data without null terminator at end
    let data = "NoTerminator".data(using: .utf8)!
    let reader = BinaryReader(data: data)
    let extractor = StringExtractor(reader: reader)

    let strings = extractor.extractCStrings(at: 0, size: data.count)

    // Should still extract the string at end of section
    XCTAssertEqual(strings.count, 1)
    XCTAssertEqual(strings[0].value, "NoTerminator")
  }

  func testExtractCStringsLongString() throws {
    // Test with a very long string - maximumLength filters complete strings
    // Note: The scanner will try to find valid strings within the data
    let longString = String(repeating: "A", count: 1000)
    var data = longString.data(using: .utf8)!
    data.append(0)

    let reader = BinaryReader(data: data)
    let extractor = StringExtractor(reader: reader)

    // With a maximum length of 500, the full 1000-char string won't be found
    // But the scanner may find shorter strings within the data
    let strings = extractor.extractCStrings(at: 0, size: data.count, maximumLength: 500)

    // The full string is 1000 chars which exceeds the limit
    // None of the strings found should exceed the maximum length
    for string in strings {
      XCTAssertLessThanOrEqual(string.value.count, 500)
    }
  }

  // MARK: - Integration with MachOBinary

  func testExtractStringsFromBinary() throws {
    let binaryPath = fixtureURL.path

    // Skip if fixture doesn't exist
    guard FileManager.default.fileExists(atPath: binaryPath) else {
      throw XCTSkip("Test fixture not found at \(binaryPath)")
    }

    let binary = try MachOBinary(path: binaryPath)
    let extractor = StringExtractor(binary: binary)

    let allStrings = try extractor.extractAllStrings()

    // Simple ARM64 binary should have at least some strings
    XCTAssertFalse(allStrings.isEmpty, "Expected to find strings in binary")
  }
}
