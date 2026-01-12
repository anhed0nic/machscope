// SuperBlob.swift
// MachOKit
//
// Code signature SuperBlob parser

import Foundation

/// Magic numbers for code signature blobs (big-endian)
public enum CodeSignatureMagic: UInt32, Sendable, CustomStringConvertible {
  case superBlob = 0xFADE_0CC0  // Embedded signature super blob
  case codeDirectory = 0xFADE_0C02  // CodeDirectory blob
  case requirements = 0xFADE_0C01  // Requirements blob
  case entitlements = 0xFADE_7171  // Embedded entitlements (XML)
  case entitlementsDER = 0xFADE_7172  // DER-encoded entitlements
  case cmsSignature = 0xFADE_0B01  // CMS signature blob (also used as blob wrapper)
  case launchConstraint = 0xFADE_8181  // Launch constraint blob

  public var description: String {
    switch self {
    case .superBlob: return "SuperBlob"
    case .codeDirectory: return "CodeDirectory"
    case .requirements: return "Requirements"
    case .entitlements: return "Entitlements (XML)"
    case .entitlementsDER: return "Entitlements (DER)"
    case .cmsSignature: return "CMS Signature"
    case .launchConstraint: return "Launch Constraint"
    }
  }
}

/// Slot types in the SuperBlob
public enum CodeSignatureSlot: UInt32, Sendable, CustomStringConvertible {
  case codeDirectory = 0  // CodeDirectory
  case infoSlot = 1  // Info.plist
  case requirements = 2  // Internal requirements
  case resourceDir = 3  // Resource directory
  case application = 4  // Application specific slot
  case entitlements = 5  // Embedded entitlements
  case repSpecific = 6  // Rep-specific slot
  case entitlementsDER = 7  // DER-encoded entitlements
  case launchConstraintSelf = 8  // Launch constraint on self
  case launchConstraintParent = 9  // Launch constraint on parent
  case launchConstraintResponsible = 10  // Launch constraint on responsible process
  case libraryConstraint = 11  // Library constraint

  // Alternate CodeDirectory slots (for multiple hash types)
  case alternateCodeDirectory1 = 0x1000
  case alternateCodeDirectory2 = 0x1001
  case alternateCodeDirectory3 = 0x1002
  case alternateCodeDirectory4 = 0x1003
  case alternateCodeDirectory5 = 0x1004

  case cmsSignature = 0x10000  // CMS signature

  public var description: String {
    switch self {
    case .codeDirectory: return "CodeDirectory"
    case .infoSlot: return "Info.plist"
    case .requirements: return "Requirements"
    case .resourceDir: return "Resource Directory"
    case .application: return "Application"
    case .entitlements: return "Entitlements"
    case .repSpecific: return "Rep Specific"
    case .entitlementsDER: return "Entitlements (DER)"
    case .launchConstraintSelf: return "Launch Constraint (Self)"
    case .launchConstraintParent: return "Launch Constraint (Parent)"
    case .launchConstraintResponsible: return "Launch Constraint (Responsible)"
    case .libraryConstraint: return "Library Constraint"
    case .alternateCodeDirectory1: return "Alternate CodeDirectory 1"
    case .alternateCodeDirectory2: return "Alternate CodeDirectory 2"
    case .alternateCodeDirectory3: return "Alternate CodeDirectory 3"
    case .alternateCodeDirectory4: return "Alternate CodeDirectory 4"
    case .alternateCodeDirectory5: return "Alternate CodeDirectory 5"
    case .cmsSignature: return "CMS Signature"
    }
  }
}

/// Entry in the SuperBlob index
public struct BlobIndex: Sendable {
  /// Slot type
  public let slotType: UInt32

  /// Parsed slot type
  public let slot: CodeSignatureSlot?

  /// Offset to the blob from the start of the SuperBlob
  public let offset: UInt32

  /// Size of a BlobIndex structure (8 bytes)
  public static let size = 8
}

/// A blob within the SuperBlob
public struct CodeSignatureBlob: Sendable {
  /// Blob magic number
  public let magic: UInt32

  /// Parsed magic type
  public let magicType: CodeSignatureMagic?

  /// Blob length (including header)
  public let length: UInt32

  /// Slot type this blob was found in
  public let slot: CodeSignatureSlot?

  /// Raw slot value
  public let rawSlot: UInt32

  /// Offset within the SuperBlob
  public let offset: UInt32

  /// Raw blob data (excluding 8-byte header)
  public let data: Data
}

/// Code signature SuperBlob container
///
/// The SuperBlob is the top-level container for all code signature data.
/// It contains an index of blobs and the blobs themselves.
public struct SuperBlob: Sendable {
  /// Magic number (should be CSMAGIC_EMBEDDED_SIGNATURE = 0xFADE0CC0)
  public let magic: UInt32

  /// Total length of the SuperBlob
  public let length: UInt32

  /// Number of blobs in the index
  public let blobCount: UInt32

  /// Index of all blobs
  public let blobIndex: [BlobIndex]

  /// All parsed blobs
  public let blobs: [CodeSignatureBlob]

  /// Minimum SuperBlob header size (magic + length + count)
  public static let headerSize = 12

  /// Parse a SuperBlob from binary data
  /// - Parameters:
  ///   - reader: BinaryReader containing the code signature data
  ///   - baseOffset: Offset within the reader where the SuperBlob starts (default: 0)
  /// - Returns: Parsed SuperBlob
  /// - Throws: MachOParseError if parsing fails
  public static func parse(from reader: BinaryReader, at baseOffset: Int = 0) throws -> SuperBlob {
    // Read header (big-endian)
    let magic = try reader.readUInt32BigEndian(at: baseOffset)

    // Validate magic
    guard magic == CodeSignatureMagic.superBlob.rawValue else {
      throw MachOParseError.invalidCodeSignatureMagic(
        expected: CodeSignatureMagic.superBlob.rawValue,
        found: magic,
        offset: baseOffset
      )
    }

    let length = try reader.readUInt32BigEndian(at: baseOffset + 4)
    let count = try reader.readUInt32BigEndian(at: baseOffset + 8)

    // Validate length
    guard length >= UInt32(headerSize) else {
      throw MachOParseError.invalidCodeSignatureLength(
        offset: baseOffset,
        length: length
      )
    }

    // Parse blob index
    var blobIndex: [BlobIndex] = []
    blobIndex.reserveCapacity(Int(count))

    var indexOffset = baseOffset + headerSize
    for _ in 0..<count {
      let slotType = try reader.readUInt32BigEndian(at: indexOffset)
      let blobOffset = try reader.readUInt32BigEndian(at: indexOffset + 4)

      let index = BlobIndex(
        slotType: slotType,
        slot: CodeSignatureSlot(rawValue: slotType),
        offset: blobOffset
      )
      blobIndex.append(index)
      indexOffset += BlobIndex.size
    }

    // Parse each blob
    var blobs: [CodeSignatureBlob] = []
    blobs.reserveCapacity(Int(count))

    for index in blobIndex {
      let blobStart = baseOffset + Int(index.offset)

      // Read blob header (big-endian)
      let blobMagic = try reader.readUInt32BigEndian(at: blobStart)
      let blobLength = try reader.readUInt32BigEndian(at: blobStart + 4)

      // Validate blob length
      guard blobLength >= 8 else {
        throw MachOParseError.invalidCodeSignatureLength(
          offset: blobStart,
          length: blobLength
        )
      }

      // Read full blob data (including 8-byte header)
      // Offsets inside blobs like CodeDirectory are relative to the blob start
      let data = try reader.readBytes(at: blobStart, count: Int(blobLength))

      let blob = CodeSignatureBlob(
        magic: blobMagic,
        magicType: CodeSignatureMagic(rawValue: blobMagic),
        length: blobLength,
        slot: index.slot,
        rawSlot: index.slotType,
        offset: index.offset,
        data: data
      )
      blobs.append(blob)
    }

    return SuperBlob(
      magic: magic,
      length: length,
      blobCount: count,
      blobIndex: blobIndex,
      blobs: blobs
    )
  }

  /// Find a blob by slot type
  /// - Parameter slot: The slot to search for
  /// - Returns: The blob at that slot, or nil if not found
  public func blob(for slot: CodeSignatureSlot) -> CodeSignatureBlob? {
    blobs.first { $0.slot == slot }
  }

  /// Get the CodeDirectory blob
  public var codeDirectoryBlob: CodeSignatureBlob? {
    blob(for: .codeDirectory)
  }

  /// Get the entitlements blob (XML format)
  public var entitlementsBlob: CodeSignatureBlob? {
    blob(for: .entitlements)
  }

  /// Get the DER entitlements blob
  public var entitlementsDERBlob: CodeSignatureBlob? {
    blob(for: .entitlementsDER)
  }

  /// Get the requirements blob
  public var requirementsBlob: CodeSignatureBlob? {
    blob(for: .requirements)
  }

  /// Get the CMS signature blob
  public var cmsSignatureBlob: CodeSignatureBlob? {
    blob(for: .cmsSignature)
  }
}

// MARK: - CustomStringConvertible

extension SuperBlob: CustomStringConvertible {
  public var description: String {
    var result = "SuperBlob:\n"
    result += "  Length: \(length) bytes\n"
    result += "  Blob Count: \(blobCount)\n"
    result += "  Blobs:\n"
    for blob in blobs {
      let slotName = blob.slot?.description ?? "Unknown(\(blob.rawSlot))"
      let magicName = blob.magicType?.description ?? String(format: "0x%08X", blob.magic)
      result += "    - \(slotName): \(magicName) (\(blob.length) bytes)\n"
    }
    return result
  }
}

extension BlobIndex: CustomStringConvertible {
  public var description: String {
    let slotName = slot?.description ?? "Unknown(\(slotType))"
    return "BlobIndex(slot: \(slotName), offset: \(offset))"
  }
}
