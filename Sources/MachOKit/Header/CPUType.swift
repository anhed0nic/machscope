// CPUType.swift
// MachOKit
//
// CPU type and subtype enums for Mach-O headers

import Foundation

/// CPU architecture type from Mach-O header
///
/// Values correspond to cpu_type_t in mach/machine.h
public enum CPUType: Int32, Sendable, Codable, CustomStringConvertible {
  /// Intel x86 32-bit
  case x86 = 7  // CPU_TYPE_X86
  /// Intel x86 64-bit
  case x86_64 = 0x0100_0007  // CPU_TYPE_X86_64
  /// ARM 32-bit
  case arm = 12  // CPU_TYPE_ARM
  /// ARM 64-bit (Apple Silicon)
  case arm64 = 0x0100_000C  // CPU_TYPE_ARM64
  /// PowerPC 32-bit
  case powerPC = 18  // CPU_TYPE_POWERPC
  /// PowerPC 64-bit
  case powerPC64 = 0x0100_0012  // CPU_TYPE_POWERPC64

  public var description: String {
    switch self {
    case .x86: return "x86"
    case .x86_64: return "x86_64"
    case .arm: return "arm"
    case .arm64: return "arm64"
    case .powerPC: return "powerpc"
    case .powerPC64: return "powerpc64"
    }
  }

  /// Whether this is a 64-bit architecture
  public var is64Bit: Bool {
    switch self {
    case .x86_64, .arm64, .powerPC64:
      return true
    case .x86, .arm, .powerPC:
      return false
    }
  }

  /// Check if this CPU type is supported for analysis
  public var isSupported: Bool {
    self == .arm64
  }
}

/// CPU subtype for more specific architecture variants
///
/// Values correspond to cpu_subtype_t in mach/machine.h
public enum CPUSubtype: Int32, Sendable, Codable, CustomStringConvertible {
  /// All subtypes (generic)
  case all = 0

  // ARM64 subtypes
  /// ARM64 v8 (base)
  case arm64v8 = 1
  /// ARM64e with pointer authentication
  case arm64e = 2

  // x86_64 subtypes
  /// x86_64 all
  case x86_64All = 3
  /// x86_64 Haswell
  case x86_64Haswell = 8

  public var description: String {
    switch self {
    case .all: return "all"
    case .arm64v8: return "arm64v8"
    case .arm64e: return "arm64e"
    case .x86_64All: return "x86_64_all"
    case .x86_64Haswell: return "x86_64_haswell"
    }
  }

  /// Whether this subtype supports pointer authentication
  public var hasPAC: Bool {
    self == .arm64e
  }
}

// MARK: - Raw Value Handling

extension CPUType {
  /// Create from raw value, returning nil for unknown types
  public init?(rawValueOrNil rawValue: Int32) {
    self.init(rawValue: rawValue)
  }

  /// Get the raw CPU type value
  public var machValue: Int32 {
    rawValue
  }
}

extension CPUSubtype {
  /// Create from raw value, returning nil for unknown types
  public init?(rawValueOrNil rawValue: Int32) {
    // Mask off the capability bits (upper 8 bits can contain flags)
    let maskedValue = rawValue & 0x00FF_FFFF
    self.init(rawValue: maskedValue)
  }

  /// Extract capability bits from raw subtype
  public static func capabilities(from rawValue: Int32) -> UInt8 {
    UInt8((rawValue >> 24) & 0xFF)
  }
}
