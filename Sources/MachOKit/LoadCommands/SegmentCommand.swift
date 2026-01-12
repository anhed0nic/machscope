// SegmentCommand.swift
// MachOKit
//
// LC_SEGMENT_64 parsing

import Foundation

/// Segment command (LC_SEGMENT_64)
///
/// Represents a memory segment containing zero or more sections
public struct SegmentCommand: Sendable {
  /// Segment name (max 16 characters)
  public let name: String

  /// Memory address of this segment
  public let vmAddress: UInt64

  /// Memory size of this segment
  public let vmSize: UInt64

  /// File offset of this segment
  public let fileOffset: UInt64

  /// File size of this segment
  public let fileSize: UInt64

  /// Maximum VM protection
  public let maxProtection: VMProtection

  /// Initial VM protection
  public let initialProtection: VMProtection

  /// Number of sections in this segment
  public let numberOfSections: UInt32

  /// Segment flags
  public let flags: UInt32

  /// Sections within this segment
  public let sections: [Section]

  /// Size of segment_command_64 structure (without sections)
  public static let structSize: Int = 72

  /// Parse a segment command from binary data
  /// - Parameters:
  ///   - reader: BinaryReader to read from
  ///   - offset: Offset of the load command
  /// - Returns: Parsed SegmentCommand
  /// - Throws: MachOParseError if parsing fails
  public static func parse(from reader: BinaryReader, at offset: Int) throws -> SegmentCommand {
    // Skip cmd (4) and cmdsize (4)
    let nameOffset = offset + 8

    // Read segment name (16 bytes, null-padded)
    let name = try reader.readFixedString(at: nameOffset, length: 16)

    // Read segment properties
    let vmAddr = try reader.readUInt64(at: offset + 24)
    let vmSize = try reader.readUInt64(at: offset + 32)
    let fileOff = try reader.readUInt64(at: offset + 40)
    let fileSize = try reader.readUInt64(at: offset + 48)
    let maxProt = try reader.readInt32(at: offset + 56)
    let initProt = try reader.readInt32(at: offset + 60)
    let nsects = try reader.readUInt32(at: offset + 64)
    let flags = try reader.readUInt32(at: offset + 68)

    // Parse sections
    var sections: [Section] = []
    sections.reserveCapacity(Int(nsects))

    var sectionOffset = offset + structSize
    for _ in 0..<nsects {
      let section = try Section.parse(from: reader, at: sectionOffset)
      sections.append(section)
      sectionOffset += Section.structSize
    }

    return SegmentCommand(
      name: name,
      vmAddress: vmAddr,
      vmSize: vmSize,
      fileOffset: fileOff,
      fileSize: fileSize,
      maxProtection: VMProtection(rawValue: maxProt),
      initialProtection: VMProtection(rawValue: initProt),
      numberOfSections: nsects,
      flags: flags,
      sections: sections
    )
  }

  /// Check if this segment contains the given virtual address
  public func contains(address: UInt64) -> Bool {
    address >= vmAddress && address < vmAddress + vmSize
  }

  /// Find a section by name
  public func section(named name: String) -> Section? {
    sections.first { $0.name == name }
  }
}

// MARK: - VM Protection

/// Virtual memory protection flags
public struct VMProtection: OptionSet, Sendable, Codable, CustomStringConvertible {
  public let rawValue: Int32

  public init(rawValue: Int32) {
    self.rawValue = rawValue
  }

  /// Read permission
  public static let read = VMProtection(rawValue: 1)

  /// Write permission
  public static let write = VMProtection(rawValue: 2)

  /// Execute permission
  public static let execute = VMProtection(rawValue: 4)

  /// Check if all permissions are set
  public var isReadWriteExecute: Bool {
    contains(.read) && contains(.write) && contains(.execute)
  }

  public var description: String {
    var result = ""
    result += contains(.read) ? "r" : "-"
    result += contains(.write) ? "w" : "-"
    result += contains(.execute) ? "x" : "-"
    return result
  }
}
