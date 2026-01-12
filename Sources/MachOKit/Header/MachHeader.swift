// MachHeader.swift
// MachOKit
//
// Mach-O header parsing

import Foundation

// MARK: - Magic Numbers

/// Mach-O magic numbers
public enum MachOMagic: UInt32, Sendable {
  /// 32-bit Mach-O (little-endian on this machine)
  case mh32 = 0xFEED_FACE
  /// 32-bit Mach-O (big-endian, needs byte swap)
  case mh32Cigam = 0xCEFA_EDFE
  /// 64-bit Mach-O (little-endian on this machine)
  case mh64 = 0xFEED_FACF
  /// 64-bit Mach-O (big-endian, needs byte swap)
  case mh64Cigam = 0xCFFA_EDFE
  /// Fat/Universal binary (big-endian)
  case fat = 0xCAFE_BABE
  /// Fat/Universal binary (little-endian, needs byte swap)
  case fatCigam = 0xBEBA_FECA
  /// Fat binary with 64-bit offsets
  case fat64 = 0xCAFE_BABF
  /// Fat binary with 64-bit offsets (needs byte swap)
  case fat64Cigam = 0xBFBA_FECA

  /// Whether this magic indicates a 64-bit binary
  public var is64Bit: Bool {
    switch self {
    case .mh64, .mh64Cigam: return true
    default: return false
    }
  }

  /// Whether this magic indicates a fat/universal binary
  public var isFat: Bool {
    switch self {
    case .fat, .fatCigam, .fat64, .fat64Cigam: return true
    default: return false
    }
  }

  /// Whether bytes need to be swapped for this magic
  public var needsByteSwap: Bool {
    switch self {
    case .mh32Cigam, .mh64Cigam, .fatCigam, .fat64Cigam: return true
    default: return false
    }
  }
}

// MARK: - File Type

/// File types for Mach-O binaries
///
/// Values correspond to filetype in mach_header
public enum FileType: UInt32, Sendable, Codable, CustomStringConvertible {
  /// Relocatable object file (.o)
  case object = 1  // MH_OBJECT
  /// Executable file
  case execute = 2  // MH_EXECUTE
  /// Fixed VM shared library (not used)
  case fvmLib = 3  // MH_FVMLIB
  /// Core dump file
  case core = 4  // MH_CORE
  /// Preloaded executable
  case preload = 5  // MH_PRELOAD
  /// Dynamic shared library (.dylib)
  case dylib = 6  // MH_DYLIB
  /// Dynamic link editor (dyld)
  case dylinker = 7  // MH_DYLINKER
  /// Bundle (.bundle)
  case bundle = 8  // MH_BUNDLE
  /// Dynamic shared library stub
  case dylibStub = 9  // MH_DYLIB_STUB
  /// Debug symbols file (.dSYM)
  case dsym = 10  // MH_DSYM
  /// Kext bundle
  case kextBundle = 11  // MH_KEXT_BUNDLE
  /// File set (macOS 11+)
  case fileSet = 12  // MH_FILESET

  public var description: String {
    switch self {
    case .object: return "object"
    case .execute: return "execute"
    case .fvmLib: return "fvmlib"
    case .core: return "core"
    case .preload: return "preload"
    case .dylib: return "dylib"
    case .dylinker: return "dylinker"
    case .bundle: return "bundle"
    case .dylibStub: return "dylib_stub"
    case .dsym: return "dsym"
    case .kextBundle: return "kext"
    case .fileSet: return "fileset"
    }
  }

  /// Human-readable description of the file type
  public var displayName: String {
    switch self {
    case .object: return "Object File"
    case .execute: return "Executable"
    case .fvmLib: return "FVM Library"
    case .core: return "Core Dump"
    case .preload: return "Preloaded Executable"
    case .dylib: return "Dynamic Library"
    case .dylinker: return "Dynamic Linker"
    case .bundle: return "Bundle"
    case .dylibStub: return "Dynamic Library Stub"
    case .dsym: return "Debug Symbols"
    case .kextBundle: return "Kernel Extension"
    case .fileSet: return "File Set"
    }
  }
}

// MARK: - Header Flags

/// Mach header flags (bitmask)
///
/// Values correspond to flags in mach_header
public struct MachHeaderFlags: OptionSet, Sendable, Codable {
  public let rawValue: UInt32

  public init(rawValue: UInt32) {
    self.rawValue = rawValue
  }

  // Basic flags
  /// No undefined references
  public static let noUndefinedRefs = MachHeaderFlags(rawValue: 0x1)
  /// Incrementally linked
  public static let incrementalLink = MachHeaderFlags(rawValue: 0x2)
  /// Dynamically linked
  public static let dynamicLink = MachHeaderFlags(rawValue: 0x4)
  /// Bind undefined refs at load
  public static let bindAtLoad = MachHeaderFlags(rawValue: 0x8)
  /// Prebound
  public static let prebound = MachHeaderFlags(rawValue: 0x10)

  // Split segments
  /// Read-only and read-write segments split
  public static let splitSegs = MachHeaderFlags(rawValue: 0x20)

  // Lazy init
  /// Lazy init of the section
  public static let lazyInit = MachHeaderFlags(rawValue: 0x40)

  // Two-level namespace
  /// Two-level namespace bindings
  public static let twolevel = MachHeaderFlags(rawValue: 0x80)

  // Force flat namespace
  /// Force flat namespace
  public static let forceFlat = MachHeaderFlags(rawValue: 0x100)

  // No multiply defined symbols
  /// No multiply defined symbols
  public static let noMultiDefs = MachHeaderFlags(rawValue: 0x200)

  // Don't fix prebinding
  /// Don't notify about prebinding
  public static let noFixPrebinding = MachHeaderFlags(rawValue: 0x400)

  // Prebindable
  /// Not prebound but can be
  public static let prebindable = MachHeaderFlags(rawValue: 0x800)

  // All modules bound
  /// All two-level modules bound
  public static let allModsBound = MachHeaderFlags(rawValue: 0x1000)

  // Subsections via symbols
  /// Safe to divide up sections via symbols
  public static let subsectionsViaSymbols = MachHeaderFlags(rawValue: 0x2000)

  // Canonical
  /// Canonicalized by unprebind
  public static let canonical = MachHeaderFlags(rawValue: 0x4000)

  // Weak defines
  /// Has external weak symbols
  public static let weakDefines = MachHeaderFlags(rawValue: 0x8000)

  // Binds to weak
  /// Uses weak symbols
  public static let bindsToWeak = MachHeaderFlags(rawValue: 0x10000)

  // Allow stack execution
  /// Allow stack execution
  public static let allowStackExecution = MachHeaderFlags(rawValue: 0x20000)

  // Root safe
  /// Safe for root processes
  public static let rootSafe = MachHeaderFlags(rawValue: 0x40000)

  // Set UID safe
  /// Safe for setuid processes
  public static let setuidSafe = MachHeaderFlags(rawValue: 0x80000)

  // No reexported dylibs
  /// No reexported dylibs
  public static let noReexportedDylibs = MachHeaderFlags(rawValue: 0x100000)

  // PIE - Position Independent Executable
  /// Randomize address space (ASLR)
  public static let pie = MachHeaderFlags(rawValue: 0x200000)

  // Dead strippable dylib
  /// Dead-strippable dylib
  public static let deadStrippableDylib = MachHeaderFlags(rawValue: 0x400000)

  // Has TLV descriptors
  /// Has thread-local variables
  public static let hasTLVDescriptors = MachHeaderFlags(rawValue: 0x800000)

  // No heap execution
  /// No heap execution
  public static let noHeapExecution = MachHeaderFlags(rawValue: 0x1000000)

  // App extension safe
  /// Safe for app extensions
  public static let appExtensionSafe = MachHeaderFlags(rawValue: 0x2000000)

  // Nlist out of sync with dyldinfo
  /// nlist symbol table may be out of sync
  public static let nlistOutOfSyncWithDyldinfo = MachHeaderFlags(rawValue: 0x4000000)

  // Simulator support
  /// Built for simulator
  public static let simSupport = MachHeaderFlags(rawValue: 0x8000000)

  // Dylib in cache
  /// Dylib is in shared cache
  public static let dylibInCache = MachHeaderFlags(rawValue: 0x8000_0000)

  /// Get human-readable flag names
  public var flagNames: [String] {
    var names: [String] = []

    if contains(.noUndefinedRefs) { names.append("NO_UNDEFS") }
    if contains(.incrementalLink) { names.append("INCRLINK") }
    if contains(.dynamicLink) { names.append("DYLDLINK") }
    if contains(.bindAtLoad) { names.append("BINDATLOAD") }
    if contains(.prebound) { names.append("PREBOUND") }
    if contains(.splitSegs) { names.append("SPLIT_SEGS") }
    if contains(.twolevel) { names.append("TWOLEVEL") }
    if contains(.forceFlat) { names.append("FORCE_FLAT") }
    if contains(.subsectionsViaSymbols) { names.append("SUBSECTIONS_VIA_SYMBOLS") }
    if contains(.weakDefines) { names.append("WEAK_DEFINES") }
    if contains(.bindsToWeak) { names.append("BINDS_TO_WEAK") }
    if contains(.allowStackExecution) { names.append("ALLOW_STACK_EXECUTION") }
    if contains(.pie) { names.append("PIE") }
    if contains(.hasTLVDescriptors) { names.append("HAS_TLV_DESCRIPTORS") }
    if contains(.noHeapExecution) { names.append("NO_HEAP_EXECUTION") }
    if contains(.appExtensionSafe) { names.append("APP_EXTENSION_SAFE") }
    if contains(.dylibInCache) { names.append("DYLIB_IN_CACHE") }

    return names
  }
}

// MARK: - MachHeader

/// Parsed Mach-O header (64-bit)
public struct MachHeader: Sendable, Codable {
  /// Magic number identifying the file type
  public let magic: UInt32
  /// CPU type
  public let cpuType: CPUType
  /// CPU subtype
  public let cpuSubtype: CPUSubtype
  /// File type (executable, dylib, etc.)
  public let fileType: FileType
  /// Number of load commands
  public let numberOfCommands: UInt32
  /// Size of all load commands in bytes
  public let sizeOfCommands: UInt32
  /// Header flags
  public let flags: MachHeaderFlags
  /// Reserved field (64-bit only)
  public let reserved: UInt32

  /// Size of a 64-bit Mach-O header
  public static let size64: Int = 32

  /// Size of a 32-bit Mach-O header
  public static let size32: Int = 28

  /// Parse a 64-bit Mach-O header from binary data
  /// - Parameters:
  ///   - reader: BinaryReader positioned at the header start
  ///   - offset: Offset within the reader (default: 0)
  /// - Returns: Parsed MachHeader
  /// - Throws: MachOParseError if parsing fails
  public static func parse(from reader: BinaryReader, at offset: Int = 0) throws -> MachHeader {
    let magic = try reader.readUInt32(at: offset)

    // Validate magic number
    guard let machMagic = MachOMagic(rawValue: magic),
      machMagic == .mh64 || machMagic == .mh64Cigam
    else {
      throw MachOParseError.invalidMagic(found: magic, at: offset)
    }

    let needsSwap = machMagic.needsByteSwap

    // Read CPU type
    let rawCPUType = try reader.readInt32(at: offset + 4)
    let cpuTypeValue = needsSwap ? rawCPUType.byteSwapped : rawCPUType

    guard let cpuType = CPUType(rawValue: cpuTypeValue) else {
      throw MachOParseError.unsupportedCPUType(cpuTypeValue)
    }

    // Read CPU subtype
    let rawCPUSubtype = try reader.readInt32(at: offset + 8)
    let cpuSubtypeValue = needsSwap ? rawCPUSubtype.byteSwapped : rawCPUSubtype
    let cpuSubtype = CPUSubtype(rawValueOrNil: cpuSubtypeValue) ?? .all

    // Read file type
    let rawFileType = try reader.readUInt32(at: offset + 12)
    let fileTypeValue = needsSwap ? rawFileType.byteSwapped : rawFileType

    guard let fileType = FileType(rawValue: fileTypeValue) else {
      // Use execute as default for unknown file types
      return MachHeader(
        magic: magic,
        cpuType: cpuType,
        cpuSubtype: cpuSubtype,
        fileType: .execute,
        numberOfCommands: try readUInt32(reader, at: offset + 16, swap: needsSwap),
        sizeOfCommands: try readUInt32(reader, at: offset + 20, swap: needsSwap),
        flags: MachHeaderFlags(rawValue: try readUInt32(reader, at: offset + 24, swap: needsSwap)),
        reserved: try readUInt32(reader, at: offset + 28, swap: needsSwap)
      )
    }

    return MachHeader(
      magic: magic,
      cpuType: cpuType,
      cpuSubtype: cpuSubtype,
      fileType: fileType,
      numberOfCommands: try readUInt32(reader, at: offset + 16, swap: needsSwap),
      sizeOfCommands: try readUInt32(reader, at: offset + 20, swap: needsSwap),
      flags: MachHeaderFlags(rawValue: try readUInt32(reader, at: offset + 24, swap: needsSwap)),
      reserved: try readUInt32(reader, at: offset + 28, swap: needsSwap)
    )
  }

  /// Helper to read UInt32 with optional byte swap
  private static func readUInt32(_ reader: BinaryReader, at offset: Int, swap: Bool) throws
    -> UInt32
  {
    let value = try reader.readUInt32(at: offset)
    return swap ? value.byteSwapped : value
  }
}

// MARK: - Codable Support

extension MachHeader {
  private enum CodingKeys: String, CodingKey {
    case magic, cpuType, cpuSubtype, fileType
    case numberOfCommands, sizeOfCommands, flags, reserved
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    magic = try container.decode(UInt32.self, forKey: .magic)
    cpuType = try container.decode(CPUType.self, forKey: .cpuType)
    cpuSubtype = try container.decode(CPUSubtype.self, forKey: .cpuSubtype)
    fileType = try container.decode(FileType.self, forKey: .fileType)
    numberOfCommands = try container.decode(UInt32.self, forKey: .numberOfCommands)
    sizeOfCommands = try container.decode(UInt32.self, forKey: .sizeOfCommands)
    flags = try container.decode(MachHeaderFlags.self, forKey: .flags)
    reserved = try container.decode(UInt32.self, forKey: .reserved)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(String(format: "0x%08x", magic), forKey: .magic)
    try container.encode(cpuType.description, forKey: .cpuType)
    try container.encode(cpuSubtype.description, forKey: .cpuSubtype)
    try container.encode(fileType.description, forKey: .fileType)
    try container.encode(numberOfCommands, forKey: .numberOfCommands)
    try container.encode(sizeOfCommands, forKey: .sizeOfCommands)
    try container.encode(flags.flagNames, forKey: .flags)
    try container.encode(reserved, forKey: .reserved)
  }
}
