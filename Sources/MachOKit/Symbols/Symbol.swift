// Symbol.swift
// MachOKit
//
// Symbol table entry

import Foundation

/// Symbol type extracted from n_type field
public enum SymbolType: UInt8, Sendable, Codable, CustomStringConvertible {
  case undefined = 0x00  // N_UNDF
  case absolute = 0x02  // N_ABS
  case section = 0x0E  // N_SECT
  case prebound = 0x0C  // N_PBUD
  case indirect = 0x0A  // N_INDR

  public var description: String {
    switch self {
    case .undefined: return "U"
    case .absolute: return "A"
    case .section: return "S"
    case .prebound: return "P"
    case .indirect: return "I"
    }
  }

  /// Extract symbol type from n_type byte
  public static func from(nType: UInt8) -> SymbolType {
    // N_TYPE mask is 0x0E
    let typeValue = nType & 0x0E
    return SymbolType(rawValue: typeValue) ?? .undefined
  }
}

/// Symbol table entry
public struct Symbol: Sendable, Equatable {
  /// Symbol name
  public let name: String

  /// Symbol address (n_value)
  public let address: UInt64

  /// Symbol type
  public let type: SymbolType

  /// Section index (0 = undefined, 1-255 = section ordinal)
  public let sectionIndex: UInt8

  /// Symbol description/flags (n_desc)
  public let description: UInt16

  /// Whether this is an external symbol
  public let isExternal: Bool

  /// Whether this is a private external symbol
  public let isPrivateExternal: Bool

  /// Whether this symbol is defined (not undefined)
  public var isDefined: Bool {
    type != .undefined
  }

  /// Whether this symbol is a debugging symbol
  public let isDebugSymbol: Bool

  /// Size of nlist_64 structure
  public static let structSize: Int = 16

  /// Create a symbol from raw nlist_64 data
  public init(
    name: String,
    nType: UInt8,
    sectionIndex: UInt8,
    description: UInt16,
    address: UInt64
  ) {
    self.name = name
    self.address = address
    self.type = SymbolType.from(nType: nType)
    self.sectionIndex = sectionIndex
    self.description = description

    // N_EXT is bit 0x01
    self.isExternal = (nType & 0x01) != 0

    // N_PEXT is bit 0x10
    self.isPrivateExternal = (nType & 0x10) != 0

    // N_STAB mask is 0xE0 - if any of these bits are set, it's a debug symbol
    self.isDebugSymbol = (nType & 0xE0) != 0
  }

  /// Create a symbol with all fields
  public init(
    name: String,
    address: UInt64,
    type: SymbolType,
    sectionIndex: UInt8,
    description: UInt16,
    isExternal: Bool,
    isPrivateExternal: Bool,
    isDebugSymbol: Bool
  ) {
    self.name = name
    self.address = address
    self.type = type
    self.sectionIndex = sectionIndex
    self.description = description
    self.isExternal = isExternal
    self.isPrivateExternal = isPrivateExternal
    self.isDebugSymbol = isDebugSymbol
  }
}

// MARK: - Symbol Comparison

extension Symbol: Comparable {
  public static func < (lhs: Symbol, rhs: Symbol) -> Bool {
    lhs.address < rhs.address
  }
}
