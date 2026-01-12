// CodeSignatureCommand.swift
// MachOKit
//
// LC_CODE_SIGNATURE parsing

import Foundation

/// Code signature load command (LC_CODE_SIGNATURE)
///
/// This command points to the code signature data in the __LINKEDIT segment.
/// The actual signature data is a SuperBlob containing CodeDirectory, entitlements, etc.
public struct CodeSignatureCommand: Sendable {
  /// Offset to code signature data in file
  public let dataOffset: UInt32

  /// Size of code signature data
  public let dataSize: UInt32

  /// Parse from binary reader
  /// - Parameters:
  ///   - reader: Binary reader
  ///   - offset: Offset of the load command
  /// - Returns: Parsed CodeSignatureCommand
  /// - Throws: MachOParseError if parsing fails
  public static func parse(from reader: BinaryReader, at offset: Int) throws -> CodeSignatureCommand
  {
    CodeSignatureCommand(
      dataOffset: try reader.readUInt32(at: offset + 8),
      dataSize: try reader.readUInt32(at: offset + 12)
    )
  }
}

// MARK: - Code Signature Data Container

/// Complete parsed code signature information
public struct CodeSignature: Sendable {
  /// The SuperBlob container
  public let superBlob: SuperBlob

  /// Parsed CodeDirectory (if present)
  public let codeDirectory: CodeDirectory?

  /// Parsed entitlements (if present)
  public let entitlements: Entitlements?

  /// Whether the binary is ad-hoc signed
  public var isAdhoc: Bool {
    codeDirectory?.isAdhoc ?? false
  }

  /// Whether the binary uses hardened runtime
  public var hasHardenedRuntime: Bool {
    codeDirectory?.hasHardenedRuntime ?? false
  }

  /// Whether the binary is linker-signed
  public var isLinkerSigned: Bool {
    codeDirectory?.isLinkerSigned ?? false
  }

  /// CDHash as hex string (identifier for the signed binary)
  public var cdHash: String? {
    codeDirectory?.cdHashString
  }

  /// Signing identifier (usually bundle ID or binary name)
  public var identifier: String? {
    codeDirectory?.identifier
  }

  /// Team identifier from signing certificate
  public var teamID: String? {
    codeDirectory?.teamID
  }

  /// Parse code signature from binary data
  /// - Parameters:
  ///   - reader: Binary reader containing the entire file
  ///   - command: The LC_CODE_SIGNATURE load command
  /// - Returns: Parsed CodeSignature
  /// - Throws: MachOParseError if parsing fails
  public static func parse(from reader: BinaryReader, command: LinkeditDataCommand) throws
    -> CodeSignature
  {
    // Read the code signature data
    let sigReader = try reader.slice(at: Int(command.dataOffset), count: Int(command.dataSize))

    // Parse the SuperBlob
    let superBlob = try SuperBlob.parse(from: sigReader)

    // Parse CodeDirectory if present
    var codeDirectory: CodeDirectory?
    if let cdBlob = superBlob.codeDirectoryBlob {
      codeDirectory = try CodeDirectory.parse(from: cdBlob.data)
    }

    // Parse entitlements if present
    // Try XML entitlements first (slot 5), then DER (slot 7)
    var entitlements: Entitlements?
    if let entBlob = superBlob.entitlementsBlob {
      // The entitlements blob should be XML, but try DER as fallback
      // The blob data includes the 8-byte header (magic + length)
      // The actual entitlements XML/DER starts after the header
      let entData = entBlob.data.count > 8 ? entBlob.data.dropFirst(8) : Data()
      if !entData.isEmpty {
        do {
          entitlements = try Entitlements.parseXML(from: Data(entData))
        } catch {
          // Try DER as fallback
          entitlements = try? Entitlements.parseDER(from: Data(entData))
        }
      }
    }
    if entitlements == nil, let derBlob = superBlob.entitlementsDERBlob {
      // DER blob also has 8-byte header
      let derData = derBlob.data.count > 8 ? derBlob.data.dropFirst(8) : Data()
      if !derData.isEmpty {
        entitlements = try? Entitlements.parseDER(from: Data(derData))
      }
    }

    return CodeSignature(
      superBlob: superBlob,
      codeDirectory: codeDirectory,
      entitlements: entitlements
    )
  }
}

// MARK: - CustomStringConvertible

extension CodeSignature: CustomStringConvertible {
  public var description: String {
    var result = "Code Signature:\n"

    if let cd = codeDirectory {
      result += "  Identifier: \(cd.identifier)\n"
      if let teamID = cd.teamID {
        result += "  Team ID: \(teamID)\n"
      }
      result += "  Flags: \(cd.flags.flagNames.joined(separator: ", "))\n"
      result += "  Hash Type: \(cd.hashType)\n"
      if let cdHash = cd.cdHashString {
        result += "  CDHash: \(cdHash)\n"
      }
    }

    if let ent = entitlements, !ent.isEmpty {
      result += "  Entitlements: \(ent.count) entries\n"
      for key in ent.keys.prefix(5) {
        result += "    - \(key)\n"
      }
      if ent.count > 5 {
        result += "    ... and \(ent.count - 5) more\n"
      }
    }

    return result
  }
}

extension CodeSignatureCommand: CustomStringConvertible {
  public var description: String {
    "CodeSignatureCommand(offset: \(dataOffset), size: \(dataSize))"
  }
}
