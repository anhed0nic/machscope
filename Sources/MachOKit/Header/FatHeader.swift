// FatHeader.swift
// MachOKit
//
// Universal (Fat) binary header parsing

import Foundation

/// Architecture descriptor in a Fat binary
public struct FatArch: Sendable, Codable {
  /// CPU type for this slice
  public let cpuType: CPUType

  /// CPU subtype for this slice
  public let cpuSubtype: CPUSubtype

  /// Offset to the Mach-O slice in the file
  public let offset: UInt32

  /// Size of the Mach-O slice
  public let size: UInt32

  /// Alignment (power of 2)
  public let alignment: UInt32

  /// Size of a fat_arch structure (32-bit)
  public static let structSize: Int = 20

  /// Size of a fat_arch_64 structure
  public static let struct64Size: Int = 32

  /// Parse a 32-bit fat_arch from binary data
  /// - Parameters:
  ///   - reader: BinaryReader to read from
  ///   - offset: Offset within the reader
  /// - Returns: Parsed FatArch
  /// - Throws: MachOParseError if parsing fails
  public static func parse(from reader: BinaryReader, at offset: Int) throws -> FatArch {
    // Fat headers are big-endian
    let rawCPUType = try reader.readUInt32BigEndian(at: offset)
    let rawCPUSubtype = try reader.readUInt32BigEndian(at: offset + 4)
    let archOffset = try reader.readUInt32BigEndian(at: offset + 8)
    let archSize = try reader.readUInt32BigEndian(at: offset + 12)
    let archAlign = try reader.readUInt32BigEndian(at: offset + 16)

    guard let cpuType = CPUType(rawValue: Int32(bitPattern: rawCPUType)) else {
      throw MachOParseError.unsupportedCPUType(Int32(bitPattern: rawCPUType))
    }

    let cpuSubtype = CPUSubtype(rawValueOrNil: Int32(bitPattern: rawCPUSubtype)) ?? .all

    return FatArch(
      cpuType: cpuType,
      cpuSubtype: cpuSubtype,
      offset: archOffset,
      size: archSize,
      alignment: archAlign
    )
  }

  /// Parse a 64-bit fat_arch_64 from binary data
  /// - Parameters:
  ///   - reader: BinaryReader to read from
  ///   - offset: Offset within the reader
  /// - Returns: Parsed FatArch (with 32-bit offset/size truncated if necessary)
  /// - Throws: MachOParseError if parsing fails
  public static func parse64(from reader: BinaryReader, at offset: Int) throws -> FatArch {
    // Fat headers are big-endian
    let rawCPUType = try reader.readUInt32BigEndian(at: offset)
    let rawCPUSubtype = try reader.readUInt32BigEndian(at: offset + 4)
    let archOffset64 = try reader.readUInt64BigEndian(at: offset + 8)
    let archSize64 = try reader.readUInt64BigEndian(at: offset + 16)
    let archAlign = try reader.readUInt32BigEndian(at: offset + 24)
    // Reserved field at offset + 28

    guard let cpuType = CPUType(rawValue: Int32(bitPattern: rawCPUType)) else {
      throw MachOParseError.unsupportedCPUType(Int32(bitPattern: rawCPUType))
    }

    let cpuSubtype = CPUSubtype(rawValueOrNil: Int32(bitPattern: rawCPUSubtype)) ?? .all

    // Note: We store as UInt32 for compatibility, but large files may need UInt64
    return FatArch(
      cpuType: cpuType,
      cpuSubtype: cpuSubtype,
      offset: UInt32(truncatingIfNeeded: archOffset64),
      size: UInt32(truncatingIfNeeded: archSize64),
      alignment: archAlign
    )
  }
}

/// Parsed Fat binary header
public struct FatHeader: Sendable {
  /// Fat binary magic number
  public let magic: UInt32

  /// Architecture descriptors for each slice
  public let architectures: [FatArch]

  /// Whether this is a 64-bit fat binary
  public let is64Bit: Bool

  /// Size of the fat header structure
  public static let headerSize: Int = 8

  /// Parse a Fat binary header from binary data
  /// - Parameter reader: BinaryReader to read from
  /// - Returns: Parsed FatHeader
  /// - Throws: MachOParseError if parsing fails
  public static func parse(from reader: BinaryReader) throws -> FatHeader {
    let magic = try reader.readUInt32(at: 0)

    guard let machMagic = MachOMagic(rawValue: magic), machMagic.isFat else {
      throw MachOParseError.invalidFatMagic(found: magic)
    }

    let is64Bit = machMagic == .fat64 || machMagic == .fat64Cigam

    // Number of architectures (big-endian)
    let nfatArch = try reader.readUInt32BigEndian(at: 4)

    guard nfatArch > 0 else {
      throw MachOParseError.emptyFatBinary
    }

    var architectures: [FatArch] = []
    architectures.reserveCapacity(Int(nfatArch))

    let archStructSize = is64Bit ? FatArch.struct64Size : FatArch.structSize

    for i in 0..<nfatArch {
      let archOffset = headerSize + Int(i) * archStructSize

      let arch =
        if is64Bit {
          try FatArch.parse64(from: reader, at: archOffset)
        } else {
          try FatArch.parse(from: reader, at: archOffset)
        }
      architectures.append(arch)
    }

    return FatHeader(
      magic: magic,
      architectures: architectures,
      is64Bit: is64Bit
    )
  }

  /// Find the architecture matching the specified CPU type
  /// - Parameter cpuType: CPU type to find
  /// - Returns: FatArch for the matching slice, or nil if not found
  public func architecture(for cpuType: CPUType) -> FatArch? {
    architectures.first { $0.cpuType == cpuType }
  }

  /// Get the preferred architecture (arm64 if available, else first)
  public var preferredArchitecture: FatArch? {
    architecture(for: .arm64) ?? architectures.first
  }

  /// Get a list of available architecture names
  public var availableArchitectureNames: [String] {
    architectures.map { $0.cpuType.description }
  }

  /// Get a formatted string of available architectures
  public var availableArchitecturesDescription: String {
    availableArchitectureNames.joined(separator: ", ")
  }
}
