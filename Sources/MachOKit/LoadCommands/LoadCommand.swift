// LoadCommand.swift
// MachOKit
//
// Base load command types and parsing

import Foundation

/// Load command type identifier
public enum LoadCommandType: UInt32, Sendable, Codable, CustomStringConvertible {
  // Segment commands
  case segment = 0x01  // LC_SEGMENT (32-bit)
  case segment64 = 0x19  // LC_SEGMENT_64

  // Symbol table commands
  case symtab = 0x02  // LC_SYMTAB
  case dysymtab = 0x0B  // LC_DYSYMTAB

  // Dynamic linker commands
  case loadDylib = 0x0C  // LC_LOAD_DYLIB
  case loadWeakDylib = 0x8000_0018  // LC_LOAD_WEAK_DYLIB (0x18 | LC_REQ_DYLD)
  case reexportDylib = 0x8000_001F  // LC_REEXPORT_DYLIB (0x1F | LC_REQ_DYLD)
  case lazyLoadDylib = 0x20  // LC_LAZY_LOAD_DYLIB
  case idDylib = 0x0D  // LC_ID_DYLIB

  // Dynamic linker info
  case loadDylinker = 0x0E  // LC_LOAD_DYLINKER
  case idDylinker = 0x0F  // LC_ID_DYLINKER

  // Code signature and related
  case codeSignature = 0x1D  // LC_CODE_SIGNATURE
  case functionStarts = 0x26  // LC_FUNCTION_STARTS
  case dataInCode = 0x29  // LC_DATA_IN_CODE
  case segmentSplitInfo = 0x1E  // LC_SEGMENT_SPLIT_INFO
  case dyldExportsTrie = 0x8000_0033  // LC_DYLD_EXPORTS_TRIE
  case dyldChainedFixups = 0x8000_0034  // LC_DYLD_CHAINED_FIXUPS

  // Entry point
  case main = 0x8000_0028  // LC_MAIN
  case unixThread = 0x05  // LC_UNIXTHREAD

  // Version info
  case buildVersion = 0x32  // LC_BUILD_VERSION
  case sourceVersion = 0x2A  // LC_SOURCE_VERSION
  case versionMinMacOS = 0x24  // LC_VERSION_MIN_MACOSX

  // Identification
  case uuid = 0x1B  // LC_UUID

  // Encryption
  case encryptionInfo64 = 0x2C  // LC_ENCRYPTION_INFO_64

  // Linker options
  case linkerOption = 0x2D  // LC_LINKER_OPTION
  case rpath = 0x8000_001C  // LC_RPATH

  // Two-level namespace
  case twolevelHints = 0x16  // LC_TWOLEVEL_HINTS
  case prebindCksum = 0x17  // LC_PREBIND_CKSUM

  public var description: String {
    switch self {
    case .segment: return "LC_SEGMENT"
    case .segment64: return "LC_SEGMENT_64"
    case .symtab: return "LC_SYMTAB"
    case .dysymtab: return "LC_DYSYMTAB"
    case .loadDylib: return "LC_LOAD_DYLIB"
    case .loadWeakDylib: return "LC_LOAD_WEAK_DYLIB"
    case .reexportDylib: return "LC_REEXPORT_DYLIB"
    case .lazyLoadDylib: return "LC_LAZY_LOAD_DYLIB"
    case .idDylib: return "LC_ID_DYLIB"
    case .loadDylinker: return "LC_LOAD_DYLINKER"
    case .idDylinker: return "LC_ID_DYLINKER"
    case .codeSignature: return "LC_CODE_SIGNATURE"
    case .functionStarts: return "LC_FUNCTION_STARTS"
    case .dataInCode: return "LC_DATA_IN_CODE"
    case .segmentSplitInfo: return "LC_SEGMENT_SPLIT_INFO"
    case .dyldExportsTrie: return "LC_DYLD_EXPORTS_TRIE"
    case .dyldChainedFixups: return "LC_DYLD_CHAINED_FIXUPS"
    case .main: return "LC_MAIN"
    case .unixThread: return "LC_UNIXTHREAD"
    case .buildVersion: return "LC_BUILD_VERSION"
    case .sourceVersion: return "LC_SOURCE_VERSION"
    case .versionMinMacOS: return "LC_VERSION_MIN_MACOSX"
    case .uuid: return "LC_UUID"
    case .encryptionInfo64: return "LC_ENCRYPTION_INFO_64"
    case .linkerOption: return "LC_LINKER_OPTION"
    case .rpath: return "LC_RPATH"
    case .twolevelHints: return "LC_TWOLEVEL_HINTS"
    case .prebindCksum: return "LC_PREBIND_CKSUM"
    }
  }
}

/// Load command payload types
public enum LoadCommandPayload: Sendable {
  case segment(SegmentCommand)
  case symtab(SymtabCommand)
  case dysymtab(DysymtabCommand)
  case dylib(DylibCommand)
  case dylinker(DylinkerCommand)
  case linkeditData(LinkeditDataCommand)
  case main(EntryPointCommand)
  case buildVersion(BuildVersionCommand)
  case sourceVersion(SourceVersionCommand)
  case uuid(UUIDCommand)
  case encryptionInfo(EncryptionInfoCommand)
  case rpath(RpathCommand)
  case raw(Data)
}

/// Base load command structure
public struct LoadCommand: Sendable {
  /// Command type
  public let type: LoadCommandType?

  /// Raw command type value (for unknown commands)
  public let rawType: UInt32

  /// Total command size
  public let size: UInt32

  /// File offset of this command
  public let offset: Int

  /// Parsed payload data
  public let payload: LoadCommandPayload

  /// Create a LoadCommand with parsed payload
  public init(
    type: LoadCommandType?,
    rawType: UInt32,
    size: UInt32,
    offset: Int,
    payload: LoadCommandPayload
  ) {
    self.type = type
    self.rawType = rawType
    self.size = size
    self.offset = offset
    self.payload = payload
  }

  /// Minimum load command size (cmd + cmdsize)
  public static let minimumSize: UInt32 = 8

  /// Parse all load commands from binary data
  /// - Parameters:
  ///   - reader: BinaryReader containing the binary data
  ///   - offset: Starting offset for load commands (after header)
  ///   - count: Number of load commands to parse
  ///   - totalSize: Total size of all load commands in bytes
  /// - Returns: Array of parsed LoadCommands
  /// - Throws: MachOParseError if parsing fails
  public static func parseAll(
    from reader: BinaryReader,
    at offset: Int,
    count: Int,
    totalSize: Int
  ) throws -> [LoadCommand] {
    var commands: [LoadCommand] = []
    commands.reserveCapacity(count)

    var currentOffset = offset

    for _ in 0..<count {
      // Ensure we have at least minimum command size
      guard reader.isInBounds(offset: currentOffset, count: Int(minimumSize)) else {
        throw MachOParseError.insufficientData(
          offset: currentOffset,
          needed: Int(minimumSize),
          available: max(0, reader.size - currentOffset)
        )
      }

      // Read command type and size
      let cmd = try reader.readUInt32(at: currentOffset)
      let cmdSize = try reader.readUInt32(at: currentOffset + 4)

      // Validate command size
      guard cmdSize >= minimumSize else {
        throw MachOParseError.invalidLoadCommandSize(
          offset: currentOffset,
          size: cmdSize
        )
      }

      // Ensure full command data is available
      guard reader.isInBounds(offset: currentOffset, count: Int(cmdSize)) else {
        throw MachOParseError.insufficientData(
          offset: currentOffset,
          needed: Int(cmdSize),
          available: max(0, reader.size - currentOffset)
        )
      }

      // Parse the command
      let command = try parseCommand(
        from: reader,
        at: currentOffset,
        type: cmd,
        size: cmdSize
      )
      commands.append(command)

      currentOffset += Int(cmdSize)
    }

    return commands
  }

  /// Parse a single load command
  private static func parseCommand(
    from reader: BinaryReader,
    at offset: Int,
    type rawType: UInt32,
    size: UInt32
  ) throws -> LoadCommand {
    let type = LoadCommandType(rawValue: rawType)

    let payload: LoadCommandPayload =
      switch type {
      case .segment64:
        try .segment(SegmentCommand.parse(from: reader, at: offset))
      case .symtab:
        try .symtab(SymtabCommand.parse(from: reader, at: offset))
      case .dysymtab:
        try .dysymtab(DysymtabCommand.parse(from: reader, at: offset))
      case .loadDylib, .loadWeakDylib, .reexportDylib, .lazyLoadDylib, .idDylib:
        try .dylib(DylibCommand.parse(from: reader, at: offset, size: size))
      case .loadDylinker, .idDylinker:
        try .dylinker(DylinkerCommand.parse(from: reader, at: offset, size: size))
      case .codeSignature, .functionStarts, .dataInCode, .segmentSplitInfo,
        .dyldExportsTrie, .dyldChainedFixups:
        try .linkeditData(LinkeditDataCommand.parse(from: reader, at: offset))
      case .main:
        try .main(EntryPointCommand.parse(from: reader, at: offset))
      case .buildVersion:
        try .buildVersion(BuildVersionCommand.parse(from: reader, at: offset, size: size))
      case .sourceVersion:
        try .sourceVersion(SourceVersionCommand.parse(from: reader, at: offset))
      case .uuid:
        try .uuid(UUIDCommand.parse(from: reader, at: offset))
      case .encryptionInfo64:
        try .encryptionInfo(EncryptionInfoCommand.parse(from: reader, at: offset))
      case .rpath:
        try .rpath(RpathCommand.parse(from: reader, at: offset, size: size))
      default:
        // Unknown command - store raw data
        .raw(try reader.readBytes(at: offset, count: Int(size)))
      }

    return LoadCommand(
      type: type,
      rawType: rawType,
      size: size,
      offset: offset,
      payload: payload
    )
  }
}

// MARK: - Supporting Command Structures

/// Dynamic symtab load command (LC_DYSYMTAB)
public struct DysymtabCommand: Sendable {
  public let localSymbolIndex: UInt32
  public let localSymbolCount: UInt32
  public let externalSymbolIndex: UInt32
  public let externalSymbolCount: UInt32
  public let undefinedSymbolIndex: UInt32
  public let undefinedSymbolCount: UInt32
  public let indirectSymbolOffset: UInt32
  public let indirectSymbolCount: UInt32

  public static func parse(from reader: BinaryReader, at offset: Int) throws -> DysymtabCommand {
    DysymtabCommand(
      localSymbolIndex: try reader.readUInt32(at: offset + 8),
      localSymbolCount: try reader.readUInt32(at: offset + 12),
      externalSymbolIndex: try reader.readUInt32(at: offset + 16),
      externalSymbolCount: try reader.readUInt32(at: offset + 20),
      undefinedSymbolIndex: try reader.readUInt32(at: offset + 24),
      undefinedSymbolCount: try reader.readUInt32(at: offset + 28),
      indirectSymbolOffset: try reader.readUInt32(at: offset + 56),
      indirectSymbolCount: try reader.readUInt32(at: offset + 60)
    )
  }
}

/// Dylinker load command (LC_LOAD_DYLINKER, LC_ID_DYLINKER)
public struct DylinkerCommand: Sendable {
  public let name: String

  public static func parse(from reader: BinaryReader, at offset: Int, size: UInt32) throws
    -> DylinkerCommand
  {
    let nameOffset = try reader.readUInt32(at: offset + 8)
    let name =
      try reader.readCString(
        at: offset + Int(nameOffset),
        maxLength: Int(size) - Int(nameOffset)
      ) ?? ""

    return DylinkerCommand(name: name)
  }
}

/// Linkedit data command (for code signature, function starts, etc.)
public struct LinkeditDataCommand: Sendable {
  public let dataOffset: UInt32
  public let dataSize: UInt32

  public static func parse(from reader: BinaryReader, at offset: Int) throws -> LinkeditDataCommand
  {
    LinkeditDataCommand(
      dataOffset: try reader.readUInt32(at: offset + 8),
      dataSize: try reader.readUInt32(at: offset + 12)
    )
  }
}

/// Entry point command (LC_MAIN)
public struct EntryPointCommand: Sendable {
  public let entryOffset: UInt64
  public let stackSize: UInt64

  public static func parse(from reader: BinaryReader, at offset: Int) throws -> EntryPointCommand {
    EntryPointCommand(
      entryOffset: try reader.readUInt64(at: offset + 8),
      stackSize: try reader.readUInt64(at: offset + 16)
    )
  }
}

/// Build version command (LC_BUILD_VERSION)
public struct BuildVersionCommand: Sendable {
  public let platform: UInt32
  public let minOS: String
  public let sdk: String
  public let numberOfTools: UInt32

  public static func parse(from reader: BinaryReader, at offset: Int, size: UInt32) throws
    -> BuildVersionCommand
  {
    let platform = try reader.readUInt32(at: offset + 8)
    let minos = try reader.readUInt32(at: offset + 12)
    let sdk = try reader.readUInt32(at: offset + 16)
    let ntools = try reader.readUInt32(at: offset + 20)

    return BuildVersionCommand(
      platform: platform,
      minOS: versionString(minos),
      sdk: versionString(sdk),
      numberOfTools: ntools
    )
  }

  private static func versionString(_ version: UInt32) -> String {
    let major = (version >> 16) & 0xFFFF
    let minor = (version >> 8) & 0xFF
    let patch = version & 0xFF
    return "\(major).\(minor).\(patch)"
  }
}

/// Source version command (LC_SOURCE_VERSION)
public struct SourceVersionCommand: Sendable {
  public let version: UInt64

  public static func parse(from reader: BinaryReader, at offset: Int) throws -> SourceVersionCommand
  {
    SourceVersionCommand(
      version: try reader.readUInt64(at: offset + 8)
    )
  }

  public var versionString: String {
    let a = (version >> 40) & 0xFFFFFF
    let b = (version >> 30) & 0x3FF
    let c = (version >> 20) & 0x3FF
    let d = (version >> 10) & 0x3FF
    let e = version & 0x3FF
    return "\(a).\(b).\(c).\(d).\(e)"
  }
}

/// UUID command (LC_UUID)
public struct UUIDCommand: Sendable {
  public let uuid: UUID

  public static func parse(from reader: BinaryReader, at offset: Int) throws -> UUIDCommand {
    let bytes = try reader.readBytes(at: offset + 8, count: 16)
    let uuid = bytes.withUnsafeBytes { buffer in
      UUID(uuid: buffer.load(as: uuid_t.self))
    }
    return UUIDCommand(uuid: uuid)
  }
}

/// Encryption info command (LC_ENCRYPTION_INFO_64)
public struct EncryptionInfoCommand: Sendable {
  public let cryptOffset: UInt32
  public let cryptSize: UInt32
  public let cryptID: UInt32

  public static func parse(from reader: BinaryReader, at offset: Int) throws
    -> EncryptionInfoCommand
  {
    EncryptionInfoCommand(
      cryptOffset: try reader.readUInt32(at: offset + 8),
      cryptSize: try reader.readUInt32(at: offset + 12),
      cryptID: try reader.readUInt32(at: offset + 16)
    )
  }
}

/// Rpath command (LC_RPATH)
public struct RpathCommand: Sendable {
  public let path: String

  public static func parse(from reader: BinaryReader, at offset: Int, size: UInt32) throws
    -> RpathCommand
  {
    let pathOffset = try reader.readUInt32(at: offset + 8)
    let path =
      try reader.readCString(
        at: offset + Int(pathOffset),
        maxLength: Int(size) - Int(pathOffset)
      ) ?? ""

    return RpathCommand(path: path)
  }
}
