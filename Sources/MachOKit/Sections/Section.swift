// Section.swift
// MachOKit
//
// Section within a segment

import Foundation

/// Section type (lower 8 bits of flags)
public enum SectionType: UInt8, Sendable, Codable, CustomStringConvertible {
  case regular = 0x00
  case zeroFill = 0x01
  case cstringLiterals = 0x02
  case fourByteLiterals = 0x03
  case eightByteLiterals = 0x04
  case literalPointers = 0x05
  case nonLazySymbolPointers = 0x06
  case lazySymbolPointers = 0x07
  case symbolStubs = 0x08
  case modInitFuncPointers = 0x09
  case modTermFuncPointers = 0x0A
  case coalesced = 0x0B
  case gbZerofill = 0x0C
  case interposing = 0x0D
  case sixteenByteLiterals = 0x0E
  case dtraceDOF = 0x0F
  case lazyDylibSymbolPointers = 0x10
  case threadLocalRegular = 0x11
  case threadLocalZerofill = 0x12
  case threadLocalVariables = 0x13
  case threadLocalVariablePointers = 0x14
  case threadLocalInitFunctionPointers = 0x15

  public var description: String {
    switch self {
    case .regular: return "regular"
    case .zeroFill: return "zerofill"
    case .cstringLiterals: return "cstring_literals"
    case .fourByteLiterals: return "4byte_literals"
    case .eightByteLiterals: return "8byte_literals"
    case .literalPointers: return "literal_pointers"
    case .nonLazySymbolPointers: return "non_lazy_symbol_pointers"
    case .lazySymbolPointers: return "lazy_symbol_pointers"
    case .symbolStubs: return "symbol_stubs"
    case .modInitFuncPointers: return "mod_init_funcs"
    case .modTermFuncPointers: return "mod_term_funcs"
    case .coalesced: return "coalesced"
    case .gbZerofill: return "gb_zerofill"
    case .interposing: return "interposing"
    case .sixteenByteLiterals: return "16byte_literals"
    case .dtraceDOF: return "dtrace_dof"
    case .lazyDylibSymbolPointers: return "lazy_dylib_symbol_pointers"
    case .threadLocalRegular: return "thread_local_regular"
    case .threadLocalZerofill: return "thread_local_zerofill"
    case .threadLocalVariables: return "thread_local_variables"
    case .threadLocalVariablePointers: return "thread_local_variable_pointers"
    case .threadLocalInitFunctionPointers: return "thread_local_init_function_pointers"
    }
  }

  /// Extract section type from flags
  public static func fromFlags(_ flags: UInt32) -> SectionType {
    SectionType(rawValue: UInt8(flags & 0xFF)) ?? .regular
  }
}

/// Section attributes (upper 24 bits of flags)
public struct SectionAttributes: OptionSet, Sendable, Codable {
  public let rawValue: UInt32

  public init(rawValue: UInt32) {
    self.rawValue = rawValue
  }

  /// Section contains only true machine instructions
  public static let pureInstructions = SectionAttributes(rawValue: 0x8000_0000)

  /// Section contains coalesced symbols
  public static let noTOC = SectionAttributes(rawValue: 0x4000_0000)

  /// Section with only code
  public static let stripStaticSyms = SectionAttributes(rawValue: 0x2000_0000)

  /// No dead stripping
  public static let noDeadStrip = SectionAttributes(rawValue: 0x1000_0000)

  /// Live support
  public static let liveSupport = SectionAttributes(rawValue: 0x0800_0000)

  /// Self modifying code
  public static let selfModifyingCode = SectionAttributes(rawValue: 0x0400_0000)

  /// Debug section
  public static let debug = SectionAttributes(rawValue: 0x0200_0000)

  /// Section has external relocation entries
  public static let extReloc = SectionAttributes(rawValue: 0x0000_0200)

  /// Section has local relocation entries
  public static let locReloc = SectionAttributes(rawValue: 0x0000_0100)

  /// Extract attributes from flags
  public static func fromFlags(_ flags: UInt32) -> SectionAttributes {
    SectionAttributes(rawValue: flags & 0xFFFF_FF00)
  }
}

/// Section within a segment
public struct Section: Sendable, Equatable {
  /// Section name (max 16 characters)
  public let name: String

  /// Segment name this section belongs to
  public let segmentName: String

  /// Memory address of this section
  public let address: UInt64

  /// Size of this section in bytes
  public let size: UInt64

  /// Offset of this section in the file
  public let offset: UInt32

  /// Alignment (power of 2)
  public let alignment: UInt32

  /// Relocation entries offset
  public let relocOffset: UInt32

  /// Number of relocation entries
  public let numberOfRelocs: UInt32

  /// Section type
  public let type: SectionType

  /// Section attributes
  public let attributes: SectionAttributes

  /// Reserved fields
  public let reserved1: UInt32
  public let reserved2: UInt32
  public let reserved3: UInt32

  /// Size of section_64 structure
  public static let structSize: Int = 80

  /// Parse a section from binary data
  /// - Parameters:
  ///   - reader: BinaryReader to read from
  ///   - offset: Offset of the section structure
  /// - Returns: Parsed Section
  /// - Throws: MachOParseError if parsing fails
  public static func parse(from reader: BinaryReader, at offset: Int) throws -> Section {
    // Section name (16 bytes)
    let name = try reader.readFixedString(at: offset, length: 16)
    // Segment name (16 bytes)
    let segmentName = try reader.readFixedString(at: offset + 16, length: 16)

    let addr = try reader.readUInt64(at: offset + 32)
    let size = try reader.readUInt64(at: offset + 40)
    let fileOffset = try reader.readUInt32(at: offset + 48)
    let align = try reader.readUInt32(at: offset + 52)
    let relocOff = try reader.readUInt32(at: offset + 56)
    let nreloc = try reader.readUInt32(at: offset + 60)
    let flags = try reader.readUInt32(at: offset + 64)
    let reserved1 = try reader.readUInt32(at: offset + 68)
    let reserved2 = try reader.readUInt32(at: offset + 72)
    let reserved3 = try reader.readUInt32(at: offset + 76)

    return Section(
      name: name,
      segmentName: segmentName,
      address: addr,
      size: size,
      offset: fileOffset,
      alignment: align,
      relocOffset: relocOff,
      numberOfRelocs: nreloc,
      type: SectionType.fromFlags(flags),
      attributes: SectionAttributes.fromFlags(flags),
      reserved1: reserved1,
      reserved2: reserved2,
      reserved3: reserved3
    )
  }

  /// Check if this section contains the given virtual address
  public func contains(address addr: UInt64) -> Bool {
    addr >= address && addr < address + size
  }

  /// Check if this section contains executable code
  public var isExecutable: Bool {
    attributes.contains(.pureInstructions)
  }

  /// Actual alignment in bytes
  public var alignmentBytes: Int {
    1 << alignment
  }
}
