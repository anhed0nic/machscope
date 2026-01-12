// SymtabCommand.swift
// MachOKit
//
// LC_SYMTAB parsing

import Foundation

/// Symbol table command (LC_SYMTAB)
///
/// Contains information about the symbol table and string table locations
public struct SymtabCommand: Sendable {
  /// Offset to symbol table in file
  public let symbolOffset: UInt32

  /// Number of symbol table entries
  public let numberOfSymbols: UInt32

  /// Offset to string table in file
  public let stringOffset: UInt32

  /// Size of string table in bytes
  public let stringSize: UInt32

  /// Parse a symtab command from binary data
  /// - Parameters:
  ///   - reader: BinaryReader to read from
  ///   - offset: Offset of the load command
  /// - Returns: Parsed SymtabCommand
  /// - Throws: MachOParseError if parsing fails
  public static func parse(from reader: BinaryReader, at offset: Int) throws -> SymtabCommand {
    // Skip cmd (4) and cmdsize (4)
    SymtabCommand(
      symbolOffset: try reader.readUInt32(at: offset + 8),
      numberOfSymbols: try reader.readUInt32(at: offset + 12),
      stringOffset: try reader.readUInt32(at: offset + 16),
      stringSize: try reader.readUInt32(at: offset + 20)
    )
  }
}
