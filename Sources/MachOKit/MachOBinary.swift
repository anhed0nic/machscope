// MachOBinary.swift
// MachOKit - Core Mach-O parsing library
//
// Main entry point for parsing Mach-O binaries

import Foundation

/// Main entry point for parsing Mach-O binaries
///
/// This struct provides a high-level interface for parsing and inspecting
/// Mach-O binary files. It supports both regular Mach-O files and Fat
/// (universal) binaries.
public struct MachOBinary: Sendable {
  /// Path to the source binary file
  public let path: String

  /// File size in bytes
  public let fileSize: UInt64

  /// Whether memory mapping is being used
  public let isMemoryMapped: Bool

  /// Parsed Mach-O header
  public let header: MachHeader

  /// All parsed load commands
  public let loadCommands: [LoadCommand]

  /// Memory segments extracted from load commands
  public let segments: [Segment]

  /// Lazy-loaded symbol table
  private let _symbolTable: SymbolTable?

  /// Reader for accessing binary data
  private let reader: BinaryReader

  // MARK: - Initialization

  /// Creates a MachOBinary by parsing the file at the given path
  /// - Parameters:
  ///   - path: Absolute path to the Mach-O binary
  ///   - architecture: For Fat binaries, which architecture to extract (default: arm64)
  /// - Throws: MachOParseError if parsing fails
  public init(path: String, architecture: CPUType = .arm64) throws {
    self.path = path

    // Get file attributes
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: path) else {
      throw MachOParseError.fileNotFound(path: path)
    }

    let attributes = try fileManager.attributesOfItem(atPath: path)
    let size = (attributes[.size] as? UInt64) ?? 0
    self.fileSize = size

    // Decide whether to use memory mapping
    self.isMemoryMapped = size > UInt64(memoryMapThreshold)

    // Load the binary data
    let reader = try loadBinary(at: path, forceMemoryMap: isMemoryMapped)

    // Check if this is a Fat binary
    let magic = try reader.readUInt32(at: 0)

    // The reader to use for data access (either full file or slice)
    let dataReader: BinaryReader

    if let machMagic = MachOMagic(rawValue: magic), machMagic.isFat {
      // Parse Fat header and extract the requested slice
      let fatHeader = try FatHeader.parse(from: reader)

      guard let arch = fatHeader.architecture(for: architecture) else {
        throw MachOParseError.architectureNotFound(architecture.description)
      }

      // Create a slice reader for this architecture
      let sliceReader = try reader.slice(
        at: Int(arch.offset),
        count: Int(arch.size)
      )

      // Parse the slice
      self.header = try MachHeader.parse(from: sliceReader)
      self.loadCommands = try LoadCommand.parseAll(
        from: sliceReader,
        at: MachHeader.size64,
        count: Int(header.numberOfCommands),
        totalSize: Int(header.sizeOfCommands)
      )

      // Use slice reader for all data access (symbols are relative to slice)
      dataReader = sliceReader
    } else {
      // Regular Mach-O binary
      self.header = try MachHeader.parse(from: reader)
      self.loadCommands = try LoadCommand.parseAll(
        from: reader,
        at: MachHeader.size64,
        count: Int(header.numberOfCommands),
        totalSize: Int(header.sizeOfCommands)
      )

      // Use full reader for data access
      dataReader = reader
    }

    self.reader = dataReader

    // Extract segments from load commands
    self.segments = loadCommands.compactMap { cmd in
      guard case .segment(let segCmd) = cmd.payload else { return nil }
      return Segment(from: segCmd)
    }

    // Lazy load symbol table
    if let symtabCmd = loadCommands.first(where: { $0.type == .symtab }),
      case .symtab(let symtab) = symtabCmd.payload
    {
      self._symbolTable = try? SymbolTable(from: dataReader, symtab: symtab)
    } else {
      self._symbolTable = nil
    }
  }

  // MARK: - Symbol Access

  /// Symbol table (lazy loaded)
  public var symbols: [Symbol]? {
    _symbolTable?.symbols
  }

  /// Find a symbol by name
  /// - Parameter name: Symbol name to find
  /// - Returns: The symbol, or nil if not found
  public func symbol(named name: String) -> Symbol? {
    _symbolTable?.symbol(named: name)
  }

  /// Find a symbol at the given address
  /// - Parameter address: Address to search for
  /// - Returns: The symbol at that address, or nil if none found
  public func symbol(at address: UInt64) -> Symbol? {
    _symbolTable?.symbol(at: address)
  }

  // MARK: - Segment Access

  /// Find a segment by name
  /// - Parameter name: Segment name (e.g., "__TEXT")
  /// - Returns: The segment, or nil if not found
  public func segment(named name: String) -> Segment? {
    segments.first { $0.name == name }
  }

  /// Find the segment containing the given address
  /// - Parameter address: Virtual address
  /// - Returns: The segment containing this address, or nil if none
  public func segment(containing address: UInt64) -> Segment? {
    segments.first { $0.contains(address: address) }
  }

  // MARK: - Section Access

  /// Get all sections across all segments
  public var allSections: [Section] {
    segments.flatMap { $0.sections }
  }

  /// Find a section by segment and section name
  /// - Parameters:
  ///   - segmentName: Segment name (e.g., "__TEXT")
  ///   - sectionName: Section name (e.g., "__text")
  /// - Returns: The section, or nil if not found
  public func section(segment segmentName: String, section sectionName: String) -> Section? {
    segment(named: segmentName)?.section(named: sectionName)
  }

  // MARK: - Data Access

  /// Read raw data from a section
  /// - Parameter section: The section to read
  /// - Returns: The section's raw data
  /// - Throws: MachOParseError if the section data is out of bounds
  public func readSectionData(_ section: Section) throws -> Data {
    try reader.readBytes(at: Int(section.offset), count: Int(section.size))
  }

  /// Read raw data from a segment
  /// - Parameter segment: The segment to read
  /// - Returns: The segment's raw data
  /// - Throws: MachOParseError if the segment data is out of bounds
  public func readSegmentData(_ segment: Segment) throws -> Data {
    try reader.readBytes(at: Int(segment.fileOffset), count: Int(segment.fileSize))
  }

  // MARK: - Load Command Queries

  /// Get all dylib dependencies
  public var dylibDependencies: [DylibCommand] {
    loadCommands.compactMap { cmd in
      guard case .dylib(let dylib) = cmd.payload else { return nil }
      return dylib
    }
  }

  /// Get the entry point (from LC_MAIN)
  public var entryPoint: EntryPointCommand? {
    for cmd in loadCommands {
      if case .main(let entry) = cmd.payload {
        return entry
      }
    }
    return nil
  }

  /// Get the UUID (from LC_UUID)
  public var uuid: UUID? {
    for cmd in loadCommands {
      if case .uuid(let uuidCmd) = cmd.payload {
        return uuidCmd.uuid
      }
    }
    return nil
  }

  /// Get the build version (from LC_BUILD_VERSION)
  public var buildVersion: BuildVersionCommand? {
    for cmd in loadCommands {
      if case .buildVersion(let version) = cmd.payload {
        return version
      }
    }
    return nil
  }

  /// Get the code signature data (from LC_CODE_SIGNATURE)
  public var codeSignatureInfo: LinkeditDataCommand? {
    for cmd in loadCommands {
      if cmd.type == .codeSignature, case .linkeditData(let data) = cmd.payload {
        return data
      }
    }
    return nil
  }

  // MARK: - Code Signature Access

  /// Parse and return the code signature
  /// - Returns: Parsed code signature, or nil if not present
  /// - Throws: MachOParseError if parsing fails
  public func parseCodeSignature() throws -> CodeSignature? {
    guard let sigInfo = codeSignatureInfo else {
      return nil
    }
    return try CodeSignature.parse(from: reader, command: sigInfo)
  }

  /// Check if the binary is code signed
  public var isSigned: Bool {
    codeSignatureInfo != nil
  }
}

// MARK: - CustomStringConvertible

extension MachOBinary: CustomStringConvertible {
  public var description: String {
    """
    MachOBinary: \(path)
    Type: \(header.fileType.displayName) (\(header.cpuType))
    Size: \(fileSize) bytes
    Segments: \(segments.count)
    Load Commands: \(loadCommands.count)
    Symbols: \(symbols?.count ?? 0)
    """
  }
}
