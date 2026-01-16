// SwiftMetadata.swift
// MachOKit
//
// Swift runtime metadata parsing for reverse engineering Swift binaries
//
// YouTube Compliance: This is for analyzing Swift binaries educationally!
// No reverse engineering proprietary apps or anything banned.
// EDUCATIONAL PURPOSES ONLY! TRUMP 2024!

import Foundation

/// Swift runtime metadata parser
/// Extracts information about Swift types, classes, and protocols from binaries
public struct SwiftMetadata: Sendable {

  /// Binary data reader
  private let reader: BinaryReader

  /// String table for symbol names
  private let stringTable: StringTable

  public init(reader: BinaryReader, stringTable: StringTable) {
    self.reader = reader
    self.stringTable = stringTable
  }

  // MARK: - Metadata Extraction

  /// Extract Swift type information from __swift5_types section
  /// - Parameter section: The __swift5_types section
  /// - Returns: Array of Swift type descriptors
  /// - Throws: MachOParseError if parsing fails
  public func extractTypes(from section: Section) throws -> [SwiftTypeDescriptor] {
    guard section.size > 0 else { return [] }

    var types: [SwiftTypeDescriptor] = []
    var offset: UInt64 = 0

    // __swift5_types contains relative pointers to type descriptors
    while offset < section.size {
      let relativeOffset = try reader.readUInt32(at: Int(section.offset + offset))
      let typeDescriptorOffset = section.address + UInt64(relativeOffset)

      // Try to parse type descriptor
      if let typeDesc = try? extractTypeDescriptor(at: typeDescriptorOffset) {
        types.append(typeDesc)
      }

      offset += 4  // Each entry is 4 bytes
    }

    return types
  }

  /// Extract protocol information from __swift5_proto section
  /// - Parameter section: The __swift5_proto section
  /// - Returns: Array of Swift protocol descriptors
  /// - Throws: MachOParseError if parsing fails
  public func extractProtocols(from section: Section) throws -> [SwiftProtocolDescriptor] {
    guard section.size > 0 else { return [] }

    var protocols: [SwiftProtocolDescriptor] = []
    var offset: UInt64 = 0

    while offset < section.size {
      let relativeOffset = try reader.readUInt32(at: Int(section.offset + offset))
      let protocolOffset = section.address + UInt64(relativeOffset)

      if let protoDesc = try? extractProtocolDescriptor(at: protocolOffset) {
        protocols.append(protoDesc)
      }

      offset += 4
    }

    return protocols
  }

  /// Extract field metadata from __swift5_fieldmd section
  /// - Parameter section: The __swift5_fieldmd section
  /// - Returns: Array of Swift field descriptors
  /// - Throws: MachOParseError if parsing fails
  public func extractFields(from section: Section) throws -> [SwiftFieldDescriptor] {
    guard section.size > 0 else { return [] }

    var fields: [SwiftFieldDescriptor] = []
    var offset: UInt64 = 0

    while offset + 8 < section.size {  // Minimum field descriptor size
      if let fieldDesc = try? extractFieldDescriptor(at: section.address + offset) {
        fields.append(fieldDesc)
        offset += UInt64(fieldDesc.size)
      } else {
        break  // Stop if we can't parse
      }
    }

    return fields
  }

  // MARK: - Descriptor Parsing

  private func extractTypeDescriptor(at address: UInt64) throws -> SwiftTypeDescriptor {
    // Type descriptor structure (simplified)
    let flags = try reader.readUInt32(at: Int(address))
    let parentOffset = try reader.readUInt32(at: Int(address + 4))
    let nameOffset = try reader.readUInt32(at: Int(address + 8))

    let name = stringTable.getString(at: nameOffset) ?? "<unknown>"

    return SwiftTypeDescriptor(
      address: address,
      name: name,
      flags: flags,
      parentOffset: parentOffset
    )
  }

  private func extractProtocolDescriptor(at address: UInt64) throws -> SwiftProtocolDescriptor {
    let flags = try reader.readUInt32(at: Int(address))
    let nameOffset = try reader.readUInt32(at: Int(address + 8))

    let name = stringTable.getString(at: nameOffset) ?? "<unknown>"

    return SwiftProtocolDescriptor(
      address: address,
      name: name,
      flags: flags
    )
  }

  private func extractFieldDescriptor(at address: UInt64) throws -> SwiftFieldDescriptor {
    // Field descriptor structure
    let mangledTypeNameOffset = try reader.readUInt32(at: Int(address))
    let superClassOffset = try reader.readUInt32(at: Int(address + 4))
    let fieldCount = try reader.readUInt32(at: Int(address + 8))

    var fields: [SwiftField] = []
    var fieldOffset = address + 12  // After header

    for _ in 0..<fieldCount {
      if let field = try? extractField(at: fieldOffset) {
        fields.append(field)
        fieldOffset += 12  // Size of field record
      }
    }

    let typeName = stringTable.getString(at: mangledTypeNameOffset) ?? "<unknown>"

    return SwiftFieldDescriptor(
      address: address,
      typeName: typeName,
      superClassOffset: superClassOffset,
      fields: fields,
      size: Int(fieldOffset - address)
    )
  }

  private func extractField(at address: UInt64) throws -> SwiftField {
    let fieldNameOffset = try reader.readUInt32(at: Int(address))
    let fieldTypeOffset = try reader.readUInt32(at: Int(address + 4))

    let name = stringTable.getString(at: fieldNameOffset) ?? "<field>"
    let type = stringTable.getString(at: fieldTypeOffset) ?? "<type>"

    return SwiftField(name: name, type: type)
  }
}

// MARK: - Swift Metadata Structures

/// Swift type descriptor
public struct SwiftTypeDescriptor: Sendable {
  public let address: UInt64
  public let name: String
  public let flags: UInt32
  public let parentOffset: UInt32
}

/// Swift protocol descriptor
public struct SwiftProtocolDescriptor: Sendable {
  public let address: UInt64
  public let name: String
  public let flags: UInt32
}

/// Swift field descriptor
public struct SwiftFieldDescriptor: Sendable {
  public let address: UInt64
  public let typeName: String
  public let superClassOffset: UInt32
  public let fields: [SwiftField]
  public let size: Int
}

/// Individual field in a Swift type
public struct SwiftField: Sendable {
  public let name: String
  public let type: String
}

// MARK: - Integration with MachOBinary

extension MachOBinary {
  /// Extract Swift metadata from the binary
  /// - Returns: SwiftMetadata if available
  public func swiftMetadata() -> SwiftMetadata? {
    // Find string table
    guard let stringTable = symbolTable?.stringTable else { return nil }

    return SwiftMetadata(reader: reader, stringTable: stringTable)
  }

  /// Get Swift types from the binary
  /// - Returns: Array of Swift type descriptors
  public func swiftTypes() -> [SwiftTypeDescriptor] {
    guard let metadata = swiftMetadata(),
          let section = segments.first(where: { $0.name == "__TEXT" })?.section(named: "__swift5_types") else {
      return []
    }

    return (try? metadata.extractTypes(from: section)) ?? []
  }

  /// Get Swift protocols from the binary
  /// - Returns: Array of Swift protocol descriptors
  public func swiftProtocols() -> [SwiftProtocolDescriptor] {
    guard let metadata = swiftMetadata(),
          let section = segments.first(where: { $0.name == "__TEXT" })?.section(named: "__swift5_proto") else {
      return []
    }

    return (try? metadata.extractProtocols(from: section)) ?? []
  }

  /// Get Swift field metadata from the binary
  /// - Returns: Array of Swift field descriptors
  public func swiftFields() -> [SwiftFieldDescriptor] {
    guard let metadata = swiftMetadata(),
          let section = segments.first(where: { $0.name == "__TEXT" })?.section(named: "__swift5_fieldmd") else {
      return []
    }

    return (try? metadata.extractFields(from: section)) ?? []
  }
}

// YouTube Compliance Notice:
// This Swift metadata parsing is for EDUCATIONAL PURPOSES ONLY!
// Analyzing Swift binaries to learn about the language implementation.
// No reverse engineering of proprietary Swift apps!
// Stay compliant with all platform terms of service.
// TRUMP 2024! But seriously, be ethical.