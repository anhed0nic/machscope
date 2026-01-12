// StringExtractor.swift
// MachOKit
//
// Extracts strings from Mach-O binary sections

import Foundation

/// Represents an extracted string from a binary
public struct ExtractedString: Sendable, Equatable, Codable {
  /// The string value
  public let value: String

  /// Offset within the file where this string was found
  public let offset: Int

  /// The section name this string was extracted from
  public let section: String

  /// Virtual address of this string (if available)
  public let address: UInt64?

  public init(value: String, offset: Int, section: String, address: UInt64? = nil) {
    self.value = value
    self.offset = offset
    self.section = section
    self.address = address
  }
}

/// Extracts strings from Mach-O binary sections
public struct StringExtractor: Sendable {
  /// The binary reader for data access
  private let reader: BinaryReader?

  /// The parsed binary (optional, for section-aware extraction)
  private let binary: MachOBinary?

  /// Default minimum string length
  public static let defaultMinimumLength = 4

  /// Default maximum string length
  public static let defaultMaximumLength = 2000

  // MARK: - Initialization

  /// Create a StringExtractor with a binary reader
  /// - Parameter reader: The reader to extract strings from
  public init(reader: BinaryReader) {
    self.reader = reader
    self.binary = nil
  }

  /// Create a StringExtractor with a parsed binary
  /// - Parameter binary: The parsed Mach-O binary
  public init(binary: MachOBinary) {
    self.binary = binary
    self.reader = nil
  }

  // MARK: - Public Extraction Methods

  /// Extract all strings from the binary
  /// - Parameters:
  ///   - minimumLength: Minimum string length to include (default: 4)
  ///   - maximumLength: Maximum string length to include (default: 2000)
  /// - Returns: Array of extracted strings
  /// - Throws: MachOParseError if extraction fails
  public func extractAllStrings(
    minimumLength: Int = defaultMinimumLength,
    maximumLength: Int = defaultMaximumLength
  ) throws -> [ExtractedString] {
    guard let binary = binary else {
      throw MachOParseError.custom(message: "Binary not available for extraction")
    }

    var allStrings: [ExtractedString] = []

    // Iterate through all sections that can contain strings
    for segment in binary.segments {
      for section in segment.sections {
        if section.type.canContainStrings || isKnownStringSection(section.name) {
          do {
            let sectionData = try binary.readSectionData(section)
            let sectionReader = BinaryReader(data: sectionData)
            let extractor = StringExtractor(reader: sectionReader)

            let strings = extractor.extractCStrings(
              at: 0,
              size: Int(section.size),
              minimumLength: minimumLength,
              maximumLength: maximumLength
            )

            // Adjust offsets to be file-relative and add address
            for string in strings {
              let fileOffset = Int(section.offset) + string.offset
              let address = section.address + UInt64(string.offset)
              let adjusted = ExtractedString(
                value: string.value,
                offset: fileOffset,
                section: section.name,
                address: address
              )
              allStrings.append(adjusted)
            }
          } catch {
            // Skip sections that can't be read
            continue
          }
        }
      }
    }

    return allStrings
  }

  /// Extract strings from a specific section
  /// - Parameters:
  ///   - segmentName: Segment name (e.g., "__TEXT")
  ///   - sectionName: Section name (e.g., "__cstring")
  ///   - minimumLength: Minimum string length
  ///   - maximumLength: Maximum string length
  /// - Returns: Array of extracted strings
  /// - Throws: MachOParseError if section not found or extraction fails
  public func extractStrings(
    from segmentName: String,
    section sectionName: String,
    minimumLength: Int = defaultMinimumLength,
    maximumLength: Int = defaultMaximumLength
  ) throws -> [ExtractedString] {
    guard let binary = binary else {
      throw MachOParseError.custom(message: "Binary not available for extraction")
    }

    guard let section = binary.section(segment: segmentName, section: sectionName) else {
      return []
    }

    let sectionData = try binary.readSectionData(section)
    let sectionReader = BinaryReader(data: sectionData)
    let extractor = StringExtractor(reader: sectionReader)

    let strings = extractor.extractCStrings(
      at: 0,
      size: Int(section.size),
      minimumLength: minimumLength,
      maximumLength: maximumLength
    )

    // Adjust offsets to be file-relative
    return strings.map { string in
      let fileOffset = Int(section.offset) + string.offset
      let address = section.address + UInt64(string.offset)
      return ExtractedString(
        value: string.value,
        offset: fileOffset,
        section: sectionName,
        address: address
      )
    }
  }

  // MARK: - Low-Level Extraction

  /// Extract C-style null-terminated strings from raw data
  /// - Parameters:
  ///   - offset: Starting offset in the reader
  ///   - size: Number of bytes to scan
  ///   - minimumLength: Minimum string length to include
  ///   - maximumLength: Maximum string length to include
  /// - Returns: Array of extracted strings with their offsets
  public func extractCStrings(
    at offset: Int,
    size: Int,
    minimumLength: Int = defaultMinimumLength,
    maximumLength: Int = defaultMaximumLength
  ) -> [ExtractedString] {
    guard let reader = reader, size > 0 else {
      return []
    }

    var strings: [ExtractedString] = []
    var currentOffset = offset
    let endOffset = offset + size

    while currentOffset < endOffset {
      // Try to read a string at this position
      if let (string, length) = readStringAt(
        reader: reader,
        offset: currentOffset,
        maxLength: min(endOffset - currentOffset, maximumLength + 1)
      ) {
        // Check if string meets criteria
        if string.count >= minimumLength && string.count <= maximumLength
          && isPrintableString(string)
        {
          let extracted = ExtractedString(
            value: string,
            offset: currentOffset - offset,  // Relative offset
            section: ""
          )
          strings.append(extracted)
        }

        // Move past this string (including null terminator)
        currentOffset += length + 1
      } else {
        // Move to next byte
        currentOffset += 1
      }
    }

    return strings
  }

  // MARK: - Private Helpers

  /// Read a null-terminated string at the given offset
  /// - Parameters:
  ///   - reader: The reader to read from
  ///   - offset: The offset to start reading
  ///   - maxLength: Maximum length to read
  /// - Returns: Tuple of (string, length without null) or nil if no valid string
  private func readStringAt(
    reader: BinaryReader,
    offset: Int,
    maxLength: Int
  ) -> (String, Int)? {
    guard offset >= 0 && offset < reader.size else {
      return nil
    }

    var bytes: [UInt8] = []
    var currentOffset = offset

    while currentOffset < reader.size && bytes.count < maxLength {
      guard let byte = try? reader.readUInt8(at: currentOffset) else {
        break
      }

      if byte == 0 {
        // Found null terminator
        break
      }

      bytes.append(byte)
      currentOffset += 1
    }

    // Empty string or hit end without null - check if we should include it
    guard !bytes.isEmpty else {
      return nil
    }

    // Try to decode as UTF-8
    guard let string = String(bytes: bytes, encoding: .utf8) else {
      return nil
    }

    return (string, bytes.count)
  }

  /// Check if a string contains only printable characters
  /// - Parameter string: The string to check
  /// - Returns: true if all characters are printable
  private func isPrintableString(_ string: String) -> Bool {
    for scalar in string.unicodeScalars {
      // Allow printable ASCII and common extended characters
      if scalar.value < 0x20 && scalar.value != 0x09 && scalar.value != 0x0A && scalar.value != 0x0D
      {
        // Non-printable control character (except tab, newline, carriage return)
        return false
      }
      if scalar.value == 0x7F {
        // DEL character
        return false
      }
    }
    return true
  }

  /// Check if a section name is known to contain strings
  /// - Parameter name: The section name
  /// - Returns: true if the section commonly contains strings
  private func isKnownStringSection(_ name: String) -> Bool {
    let knownStringSections = [
      "__cstring",
      "__oslogstring",
      "__ustring",
      "__cfstring",
      "__objc_methname",
      "__objc_classname",
      "__objc_methtype",
    ]
    return knownStringSections.contains(name)
  }
}

// MARK: - SectionType Extension

extension SectionType {
  /// Whether this section type can contain strings
  public var canContainStrings: Bool {
    switch self {
    case .cstringLiterals:
      return true
    case .fourByteLiterals, .eightByteLiterals, .sixteenByteLiterals:
      // These might contain string-like data
      return true
    case .literalPointers:
      // Contains pointers to literals
      return false
    default:
      return false
    }
  }
}
