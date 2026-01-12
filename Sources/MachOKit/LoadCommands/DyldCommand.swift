// DyldCommand.swift
// MachOKit
//
// LC_LOAD_DYLIB and related parsing

import Foundation

/// Dynamic library command (LC_LOAD_DYLIB, LC_ID_DYLIB, etc.)
///
/// Contains information about a dynamic library dependency
public struct DylibCommand: Sendable {
  /// Library path (e.g., "/usr/lib/libSystem.B.dylib")
  public let name: String

  /// Library timestamp
  public let timestamp: UInt32

  /// Current version (packed format: X.Y.Z)
  public let currentVersion: UInt32

  /// Compatibility version (packed format: X.Y.Z)
  public let compatibilityVersion: UInt32

  /// Parse a dylib command from binary data
  /// - Parameters:
  ///   - reader: BinaryReader to read from
  ///   - offset: Offset of the load command
  ///   - size: Size of the load command
  /// - Returns: Parsed DylibCommand
  /// - Throws: MachOParseError if parsing fails
  public static func parse(from reader: BinaryReader, at offset: Int, size: UInt32) throws
    -> DylibCommand
  {
    // Skip cmd (4) and cmdsize (4)
    // dylib structure starts at offset + 8:
    //   lc_str name (offset within command)
    //   uint32 timestamp
    //   uint32 current_version
    //   uint32 compatibility_version

    let nameOffset = try reader.readUInt32(at: offset + 8)
    let timestamp = try reader.readUInt32(at: offset + 12)
    let currentVersion = try reader.readUInt32(at: offset + 16)
    let compatVersion = try reader.readUInt32(at: offset + 20)

    // Read the library name string
    let name =
      try reader.readCString(
        at: offset + Int(nameOffset),
        maxLength: Int(size) - Int(nameOffset)
      ) ?? ""

    return DylibCommand(
      name: name,
      timestamp: timestamp,
      currentVersion: currentVersion,
      compatibilityVersion: compatVersion
    )
  }

  /// Get the current version as a human-readable string
  public var currentVersionString: String {
    versionString(currentVersion)
  }

  /// Get the compatibility version as a human-readable string
  public var compatibilityVersionString: String {
    versionString(compatibilityVersion)
  }

  /// Convert a packed version number to string format
  private func versionString(_ version: UInt32) -> String {
    let major = (version >> 16) & 0xFFFF
    let minor = (version >> 8) & 0xFF
    let patch = version & 0xFF
    return "\(major).\(minor).\(patch)"
  }
}
