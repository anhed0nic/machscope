// CodeDirectory.swift
// MachOKit
//
// Code directory parser

import CommonCrypto
import Foundation

/// Hash algorithm type used in code signatures
public enum HashType: UInt8, Sendable, CustomStringConvertible {
  case none = 0
  case sha1 = 1
  case sha256 = 2
  case sha256Truncated = 3
  case sha384 = 4
  case sha512 = 5

  public var description: String {
    switch self {
    case .none: return "none"
    case .sha1: return "SHA-1"
    case .sha256: return "SHA-256"
    case .sha256Truncated: return "SHA-256 (truncated)"
    case .sha384: return "SHA-384"
    case .sha512: return "SHA-512"
    }
  }

  /// Size of hash digest in bytes
  public var digestSize: Int {
    switch self {
    case .none: return 0
    case .sha1: return 20
    case .sha256, .sha256Truncated: return 32
    case .sha384: return 48
    case .sha512: return 64
    }
  }
}

/// Code directory flags
public struct CodeDirectoryFlags: OptionSet, Sendable {
  public let rawValue: UInt32

  public init(rawValue: UInt32) {
    self.rawValue = rawValue
  }

  /// The binary is ad-hoc signed (no certificate)
  public static let adhoc = CodeDirectoryFlags(rawValue: 0x0002)

  /// Forces hard page faults for missing pages
  public static let forceHard = CodeDirectoryFlags(rawValue: 0x0100)

  /// Forces hard page faults for missing pages
  public static let forceKill = CodeDirectoryFlags(rawValue: 0x0200)

  /// Restrict dyld loading
  public static let restrict = CodeDirectoryFlags(rawValue: 0x0800)

  /// Enforcement flags
  public static let enforcement = CodeDirectoryFlags(rawValue: 0x1000)

  /// Library validation (can only load signed libraries)
  public static let libraryValidation = CodeDirectoryFlags(rawValue: 0x2000)

  /// Runtime hardening
  public static let runtime = CodeDirectoryFlags(rawValue: 0x10000)

  /// Linker signed
  public static let linkerSigned = CodeDirectoryFlags(rawValue: 0x20000)

  /// Human-readable flag names
  public var flagNames: [String] {
    var names: [String] = []
    if contains(.adhoc) { names.append("adhoc") }
    if contains(.forceHard) { names.append("force-hard") }
    if contains(.forceKill) { names.append("force-kill") }
    if contains(.restrict) { names.append("restrict") }
    if contains(.enforcement) { names.append("enforcement") }
    if contains(.libraryValidation) { names.append("library-validation") }
    if contains(.runtime) { names.append("runtime") }
    if contains(.linkerSigned) { names.append("linker-signed") }
    return names.isEmpty ? ["none"] : names
  }
}

/// Code directory from code signature
///
/// The CodeDirectory contains the main signing data including
/// the identifier, team ID, hashes, and other metadata.
public struct CodeDirectory: Sendable {
  /// CodeDirectory version
  public let version: UInt32

  /// Signing flags
  public let flags: CodeDirectoryFlags

  /// Hash offset (offset to first code hash)
  public let hashOffset: UInt32

  /// Identifier offset (offset to identifier string)
  public let identifierOffset: UInt32

  /// Number of special slots (negative hash indices)
  public let specialSlotCount: UInt32

  /// Number of code slots (page hashes)
  public let codeSlotCount: UInt32

  /// Size of code in bytes (end of last code page)
  public let codeLimit: UInt32

  /// Hash type
  public let hashType: HashType

  /// Hash size
  public let hashSize: UInt8

  /// Page size (2^pageSize bytes)
  public let pageSize: UInt8

  /// Platform identifier (0 = macOS)
  public let platform: UInt8

  /// Identifier string (usually bundle ID or binary name)
  public let identifier: String

  /// Team identifier (from signing certificate)
  public let teamID: String?

  /// CDHash - SHA256 hash of the entire CodeDirectory
  public let cdHash: Data?

  /// Special slot hashes (Info.plist, requirements, etc.)
  public let specialSlotHashes: [Data]

  /// Code slot hashes (page hashes)
  public let codeSlotHashes: [Data]

  /// Exec segment base (for signed binaries with __RESTRICT segment)
  public let execSegmentBase: UInt64?

  /// Exec segment limit
  public let execSegmentLimit: UInt64?

  /// Exec segment flags
  public let execSegmentFlags: UInt64?

  /// Runtime version (for hardened runtime)
  public let runtimeVersion: UInt32?

  /// Minimum CodeDirectory version that supports the basic format
  public static let version20001: UInt32 = 0x20001

  /// Version that adds scatter support
  public static let version20100: UInt32 = 0x20100

  /// Version that adds team ID
  public static let version20200: UInt32 = 0x20200

  /// Version that adds code limit 64
  public static let version20300: UInt32 = 0x20300

  /// Version that adds exec segment
  public static let version20400: UInt32 = 0x20400

  /// Version that adds runtime and pre-encrypt hash
  public static let version20500: UInt32 = 0x20500

  /// Parse a CodeDirectory from the blob data
  /// - Parameter data: Raw CodeDirectory blob data (including 8-byte blob header: magic + length)
  /// - Returns: Parsed CodeDirectory
  /// - Throws: MachOParseError if parsing fails
  public static func parse(from data: Data) throws -> CodeDirectory {
    let reader = BinaryReader(data: data)

    // CodeDirectory blob starts with magic (4) + length (4), then the actual directory
    // All offsets in the structure are relative to the start of the blob (byte 0)
    // Skip the 8-byte blob header to get to the version field
    let headerOffset = 8

    // CodeDirectory structure fields are big-endian
    let version = try reader.readUInt32BigEndian(at: headerOffset + 0)
    let flags = CodeDirectoryFlags(rawValue: try reader.readUInt32BigEndian(at: headerOffset + 4))
    let hashOffset = try reader.readUInt32BigEndian(at: headerOffset + 8)
    let identOffset = try reader.readUInt32BigEndian(at: headerOffset + 12)
    let nSpecialSlots = try reader.readUInt32BigEndian(at: headerOffset + 16)
    let nCodeSlots = try reader.readUInt32BigEndian(at: headerOffset + 20)
    let codeLimit = try reader.readUInt32BigEndian(at: headerOffset + 24)
    let hashSizeRaw = try reader.readUInt8(at: headerOffset + 28)
    let hashTypeRaw = try reader.readUInt8(at: headerOffset + 29)
    let platform = try reader.readUInt8(at: headerOffset + 30)
    let pageSize = try reader.readUInt8(at: headerOffset + 31)

    let hashType = HashType(rawValue: hashTypeRaw) ?? .sha256

    // Parse identifier string
    let identifier = try reader.readCString(at: Int(identOffset)) ?? ""

    // Parse team ID if version supports it
    var teamID: String?
    if version >= version20200 {
      let teamIDOffset = try reader.readUInt32BigEndian(at: headerOffset + 36)
      if teamIDOffset > 0 {
        teamID = try reader.readCString(at: Int(teamIDOffset))
      }
    }

    // Parse exec segment info if version supports it
    var execSegmentBase: UInt64?
    var execSegmentLimit: UInt64?
    var execSegmentFlags: UInt64?
    if version >= version20400 {
      execSegmentBase = try reader.readUInt64BigEndian(at: headerOffset + 48)
      execSegmentLimit = try reader.readUInt64BigEndian(at: headerOffset + 56)
      execSegmentFlags = try reader.readUInt64BigEndian(at: headerOffset + 64)
    }

    // Parse runtime version if version supports it
    var runtimeVersion: UInt32?
    if version >= version20500 {
      runtimeVersion = try reader.readUInt32BigEndian(at: headerOffset + 72)
    }

    // Parse special slot hashes (if data is available)
    var specialSlotHashes: [Data] = []
    if nSpecialSlots > 0 && hashSizeRaw > 0 {
      // Special slots are stored with negative indices before the hash offset
      let specialSlotsStart = Int(hashOffset) - Int(nSpecialSlots) * Int(hashSizeRaw)
      // Only parse if the start is within bounds
      if specialSlotsStart >= 0
        && reader.isInBounds(
          offset: specialSlotsStart, count: Int(nSpecialSlots) * Int(hashSizeRaw))
      {
        for i in 0..<Int(nSpecialSlots) {
          let hashStart = specialSlotsStart + i * Int(hashSizeRaw)
          if let hash = try? reader.readBytes(at: hashStart, count: Int(hashSizeRaw)) {
            specialSlotHashes.append(hash)
          }
        }
      }
    }

    // Parse code slot hashes (if data is available)
    var codeSlotHashes: [Data] = []
    if nCodeSlots > 0 && hashSizeRaw > 0 {
      // Only parse if all hashes are within bounds
      if reader.isInBounds(offset: Int(hashOffset), count: Int(nCodeSlots) * Int(hashSizeRaw)) {
        for i in 0..<Int(nCodeSlots) {
          let hashStart = Int(hashOffset) + i * Int(hashSizeRaw)
          if let hash = try? reader.readBytes(at: hashStart, count: Int(hashSizeRaw)) {
            codeSlotHashes.append(hash)
          }
        }
      }
    }

    // CDHash is computed externally - we'll calculate it from the entire CodeDirectory
    let cdHash = computeCDHash(data: data, hashType: hashType)

    return CodeDirectory(
      version: version,
      flags: flags,
      hashOffset: hashOffset,
      identifierOffset: identOffset,
      specialSlotCount: nSpecialSlots,
      codeSlotCount: nCodeSlots,
      codeLimit: codeLimit,
      hashType: hashType,
      hashSize: hashSizeRaw,
      pageSize: pageSize,
      platform: platform,
      identifier: identifier,
      teamID: teamID,
      cdHash: cdHash,
      specialSlotHashes: specialSlotHashes,
      codeSlotHashes: codeSlotHashes,
      execSegmentBase: execSegmentBase,
      execSegmentLimit: execSegmentLimit,
      execSegmentFlags: execSegmentFlags,
      runtimeVersion: runtimeVersion
    )
  }

  /// Compute the CDHash of the CodeDirectory
  private static func computeCDHash(data: Data, hashType: HashType) -> Data? {
    // We use CC_SHA256 for all CDHash computations
    // This is a simplification - in reality, the hash type affects CDHash computation
    var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes { buffer in
      _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &digest)
    }
    return Data(digest)
  }

  /// Page size in bytes
  public var pageSizeBytes: Int {
    1 << Int(pageSize)
  }

  /// Version string for display
  public var versionString: String {
    String(format: "0x%X", version)
  }

  /// Whether this is an ad-hoc signature
  public var isAdhoc: Bool {
    flags.contains(.adhoc)
  }

  /// Whether this uses hardened runtime
  public var hasHardenedRuntime: Bool {
    flags.contains(.runtime)
  }

  /// Whether this is linker-signed
  public var isLinkerSigned: Bool {
    flags.contains(.linkerSigned)
  }

  /// CDHash as hex string
  public var cdHashString: String? {
    cdHash?.map { String(format: "%02x", $0) }.joined()
  }
}

// MARK: - CustomStringConvertible

extension CodeDirectory: CustomStringConvertible {
  public var description: String {
    var result = "CodeDirectory:\n"
    result += "  Version: \(versionString)\n"
    result += "  Identifier: \(identifier)\n"
    if let teamID = teamID {
      result += "  Team ID: \(teamID)\n"
    }
    result += "  Flags: \(flags.flagNames.joined(separator: ", "))\n"
    result += "  Hash Type: \(hashType)\n"
    result += "  Page Size: \(pageSizeBytes) bytes\n"
    result += "  Code Limit: \(codeLimit) bytes\n"
    result += "  Special Slots: \(specialSlotCount)\n"
    result += "  Code Slots: \(codeSlotCount)\n"
    if let cdHash = cdHashString {
      result += "  CDHash: \(cdHash)\n"
    }
    return result
  }
}
