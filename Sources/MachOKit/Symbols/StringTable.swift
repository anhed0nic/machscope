// StringTable.swift
// MachOKit
//
// String table for symbol names

import Foundation

/// String table for symbol names
///
/// The string table is a contiguous block of null-terminated strings.
/// Each symbol references its name by an offset into this table.
public struct StringTable: Sendable {
  /// Raw string table data
  private let data: Data

  /// Cache of already-resolved strings for performance
  private var cache: [UInt32: String]

  /// Create a string table from raw data
  public init(data: Data) {
    self.data = data
    self.cache = [:]
  }

  /// Get the string at the specified offset
  /// - Parameter offset: Byte offset into the string table
  /// - Returns: The null-terminated string at that offset, or empty string if invalid
  public mutating func string(at offset: UInt32) -> String {
    // Check cache first
    if let cached = cache[offset] {
      return cached
    }

    // Validate offset
    guard offset < data.count else {
      return ""
    }

    // Find null terminator
    let startIndex = data.startIndex + Int(offset)
    var endIndex = startIndex

    while endIndex < data.endIndex && data[endIndex] != 0 {
      endIndex += 1
    }

    // Extract and decode the string
    let stringData = data[startIndex..<endIndex]
    let result = String(data: stringData, encoding: .utf8) ?? ""

    // Cache the result
    cache[offset] = result

    return result
  }

  /// Total size of the string table
  public var size: Int {
    data.count
  }
}

// MARK: - Non-mutating Access

extension StringTable {
  /// Get the string at the specified offset (non-mutating version)
  /// - Parameter offset: Byte offset into the string table
  /// - Returns: The null-terminated string at that offset
  public func getString(at offset: UInt32) -> String {
    guard offset < data.count else {
      return ""
    }

    let startIndex = data.startIndex + Int(offset)
    var endIndex = startIndex

    while endIndex < data.endIndex && data[endIndex] != 0 {
      endIndex += 1
    }

    let stringData = data[startIndex..<endIndex]
    return String(data: stringData, encoding: .utf8) ?? ""
  }
}
