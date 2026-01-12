// BinaryReader.swift
// MachOKit
//
// Bounds-checked binary reading

import Foundation

/// Protocol for providing binary data with bounds checking
public protocol BinaryProviding: Sendable {
  /// Total size of the binary data in bytes
  var size: Int { get }

  /// Read bytes at the specified offset
  /// - Parameters:
  ///   - offset: The byte offset to read from
  ///   - count: The number of bytes to read
  /// - Returns: The bytes as Data
  /// - Throws: MachOParseError.insufficientData if out of bounds
  func readBytes(at offset: Int, count: Int) throws -> Data
}

/// Bounds-checked binary reader for safe Mach-O parsing
public struct BinaryReader: Sendable {
  /// The underlying data source
  private let data: Data

  /// Total size of the data
  public var size: Int { data.count }

  /// Current read position (for sequential reading)
  public private(set) var position: Int

  /// Create a BinaryReader from Data
  /// - Parameter data: The binary data to read
  public init(data: Data) {
    self.data = data
    self.position = 0
  }

  /// Create a BinaryReader from a BinaryProviding source
  /// - Parameter provider: The binary data provider
  /// - Throws: If the provider cannot be read
  public init(provider: any BinaryProviding) throws {
    self.data = try provider.readBytes(at: 0, count: provider.size)
    self.position = 0
  }

  // MARK: - Bounds Checking

  /// Check if the specified range is within bounds
  /// - Parameters:
  ///   - offset: Starting offset
  ///   - count: Number of bytes needed
  /// - Returns: true if the range is valid
  public func isInBounds(offset: Int, count: Int) -> Bool {
    offset >= 0 && count >= 0 && offset <= size && (size - offset) >= count
  }

  /// Validate that the specified range is within bounds
  /// - Parameters:
  ///   - offset: Starting offset
  ///   - count: Number of bytes needed
  /// - Throws: MachOParseError.insufficientData if out of bounds
  private func validateBounds(offset: Int, count: Int) throws {
    guard isInBounds(offset: offset, count: count) else {
      throw MachOParseError.insufficientData(
        offset: offset,
        needed: count,
        available: max(0, size - offset)
      )
    }
  }

  // MARK: - Reading Primitives (Little-Endian)

  /// Read a UInt8 at the specified offset
  /// - Parameter offset: The byte offset
  /// - Returns: The value read
  /// - Throws: MachOParseError.insufficientData if out of bounds
  public func readUInt8(at offset: Int) throws -> UInt8 {
    try validateBounds(offset: offset, count: 1)
    return data[data.startIndex + offset]
  }

  /// Read a UInt16 (little-endian) at the specified offset
  /// - Parameter offset: The byte offset
  /// - Returns: The value read
  /// - Throws: MachOParseError.insufficientData if out of bounds
  public func readUInt16(at offset: Int) throws -> UInt16 {
    try validateBounds(offset: offset, count: 2)
    return data.withUnsafeBytes { buffer in
      buffer.load(fromByteOffset: offset, as: UInt16.self)
    }
  }

  /// Read a UInt32 (little-endian) at the specified offset
  /// - Parameter offset: The byte offset
  /// - Returns: The value read
  /// - Throws: MachOParseError.insufficientData if out of bounds
  public func readUInt32(at offset: Int) throws -> UInt32 {
    try validateBounds(offset: offset, count: 4)
    return data.withUnsafeBytes { buffer in
      buffer.load(fromByteOffset: offset, as: UInt32.self)
    }
  }

  /// Read a UInt64 (little-endian) at the specified offset
  /// - Parameter offset: The byte offset
  /// - Returns: The value read
  /// - Throws: MachOParseError.insufficientData if out of bounds
  public func readUInt64(at offset: Int) throws -> UInt64 {
    try validateBounds(offset: offset, count: 8)
    return data.withUnsafeBytes { buffer in
      buffer.load(fromByteOffset: offset, as: UInt64.self)
    }
  }

  /// Read an Int32 (little-endian) at the specified offset
  /// - Parameter offset: The byte offset
  /// - Returns: The value read
  /// - Throws: MachOParseError.insufficientData if out of bounds
  public func readInt32(at offset: Int) throws -> Int32 {
    try validateBounds(offset: offset, count: 4)
    return data.withUnsafeBytes { buffer in
      buffer.load(fromByteOffset: offset, as: Int32.self)
    }
  }

  // MARK: - Reading Primitives (Big-Endian)

  /// Read a UInt32 (big-endian) at the specified offset
  /// Used for Fat binary headers and code signature data which are big-endian
  /// - Parameter offset: The byte offset
  /// - Returns: The value read
  /// - Throws: MachOParseError.insufficientData if out of bounds
  public func readUInt32BigEndian(at offset: Int) throws -> UInt32 {
    try validateBounds(offset: offset, count: 4)
    // Read byte-by-byte to avoid alignment issues
    let b0 = UInt32(data[data.startIndex + offset])
    let b1 = UInt32(data[data.startIndex + offset + 1])
    let b2 = UInt32(data[data.startIndex + offset + 2])
    let b3 = UInt32(data[data.startIndex + offset + 3])
    return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
  }

  /// Read a UInt64 (big-endian) at the specified offset
  /// - Parameter offset: The byte offset
  /// - Returns: The value read
  /// - Throws: MachOParseError.insufficientData if out of bounds
  public func readUInt64BigEndian(at offset: Int) throws -> UInt64 {
    try validateBounds(offset: offset, count: 8)
    // Read byte-by-byte to avoid alignment issues
    let b0 = UInt64(data[data.startIndex + offset])
    let b1 = UInt64(data[data.startIndex + offset + 1])
    let b2 = UInt64(data[data.startIndex + offset + 2])
    let b3 = UInt64(data[data.startIndex + offset + 3])
    let b4 = UInt64(data[data.startIndex + offset + 4])
    let b5 = UInt64(data[data.startIndex + offset + 5])
    let b6 = UInt64(data[data.startIndex + offset + 6])
    let b7 = UInt64(data[data.startIndex + offset + 7])
    return (b0 << 56) | (b1 << 48) | (b2 << 40) | (b3 << 32) | (b4 << 24) | (b5 << 16) | (b6 << 8)
      | b7
  }

  // MARK: - Reading Complex Types

  /// Read raw bytes at the specified offset
  /// - Parameters:
  ///   - offset: The byte offset
  ///   - count: Number of bytes to read
  /// - Returns: The bytes as Data (always starting at index 0)
  /// - Throws: MachOParseError.insufficientData if out of bounds
  public func readBytes(at offset: Int, count: Int) throws -> Data {
    try validateBounds(offset: offset, count: count)
    let start = data.startIndex + offset
    let end = start + count
    // Use subdata to get a new Data with indices starting at 0
    return data.subdata(in: start..<end)
  }

  /// Read a null-terminated C string at the specified offset
  /// - Parameters:
  ///   - offset: The byte offset
  ///   - maxLength: Maximum length to read (default: 256)
  /// - Returns: The string, or nil if invalid UTF-8
  /// - Throws: MachOParseError.insufficientData if out of bounds
  public func readCString(at offset: Int, maxLength: Int = 256) throws -> String? {
    try validateBounds(offset: offset, count: 1)

    var length = 0
    let maxPossible = min(maxLength, size - offset)

    while length < maxPossible {
      let byte = data[data.startIndex + offset + length]
      if byte == 0 { break }
      length += 1
    }

    guard length > 0 else { return "" }

    let bytes = try readBytes(at: offset, count: length)
    return String(data: bytes, encoding: .utf8)
  }

  /// Read a fixed-length string (padded with nulls)
  /// Used for segment and section names in Mach-O (16 bytes)
  /// - Parameters:
  ///   - offset: The byte offset
  ///   - length: Fixed length to read
  /// - Returns: The string with trailing nulls removed
  /// - Throws: MachOParseError.insufficientData if out of bounds
  public func readFixedString(at offset: Int, length: Int) throws -> String {
    let bytes = try readBytes(at: offset, count: length)

    // Find the first null byte or use entire length
    var actualLength = 0
    for i in 0..<length {
      if bytes[bytes.startIndex + i] == 0 { break }
      actualLength += 1
    }

    let trimmed = bytes[bytes.startIndex..<(bytes.startIndex + actualLength)]
    return String(data: trimmed, encoding: .utf8) ?? ""
  }

  // MARK: - Sequential Reading

  /// Read a UInt32 at the current position and advance
  /// - Returns: The value read
  /// - Throws: MachOParseError.insufficientData if out of bounds
  public mutating func readUInt32() throws -> UInt32 {
    let value = try readUInt32(at: position)
    position += 4
    return value
  }

  /// Read a UInt64 at the current position and advance
  /// - Returns: The value read
  /// - Throws: MachOParseError.insufficientData if out of bounds
  public mutating func readUInt64() throws -> UInt64 {
    let value = try readUInt64(at: position)
    position += 8
    return value
  }

  /// Seek to a new position
  /// - Parameter offset: The new position
  /// - Throws: MachOParseError.insufficientData if position is invalid
  public mutating func seek(to offset: Int) throws {
    guard offset >= 0 && offset <= size else {
      throw MachOParseError.insufficientData(
        offset: offset,
        needed: 0,
        available: size
      )
    }
    position = offset
  }

  /// Skip forward by the specified number of bytes
  /// - Parameter count: Number of bytes to skip
  /// - Throws: MachOParseError.insufficientData if new position is invalid
  public mutating func skip(_ count: Int) throws {
    try seek(to: position + count)
  }

  // MARK: - Slicing

  /// Create a new reader for a subrange of the data
  /// - Parameters:
  ///   - offset: Starting offset
  ///   - count: Number of bytes for the slice
  /// - Returns: A new BinaryReader for the subrange
  /// - Throws: MachOParseError.insufficientData if out of bounds
  public func slice(at offset: Int, count: Int) throws -> BinaryReader {
    let sliceData = try readBytes(at: offset, count: count)
    return BinaryReader(data: sliceData)
  }
}

// MARK: - BinaryProviding Conformance

extension BinaryReader: BinaryProviding {}
