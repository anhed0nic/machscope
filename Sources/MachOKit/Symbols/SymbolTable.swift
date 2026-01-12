// SymbolTable.swift
// MachOKit
//
// Symbol table with lazy loading support

import Foundation

/// Symbol table with lazy loading support
///
/// Provides efficient access to symbol data by loading symbols
/// on demand rather than all at once.
public struct SymbolTable: Sendable {
  /// Parsed symbols
  public let symbols: [Symbol]

  /// Index for name-based lookup
  private let nameIndex: [String: Int]

  /// Index for address-based lookup (sorted by address)
  private let addressIndex: [Symbol]

  /// Create a symbol table from raw binary data
  /// - Parameters:
  ///   - reader: BinaryReader containing the binary
  ///   - symtab: The LC_SYMTAB command with offsets
  /// - Throws: MachOParseError if parsing fails
  public init(from reader: BinaryReader, symtab: SymtabCommand) throws {
    // Load string table first
    let stringData = try reader.readBytes(
      at: Int(symtab.stringOffset),
      count: Int(symtab.stringSize)
    )
    var stringTable = StringTable(data: stringData)

    // Parse all symbols
    var symbols: [Symbol] = []
    symbols.reserveCapacity(Int(symtab.numberOfSymbols))

    var nameIndex: [String: Int] = [:]
    nameIndex.reserveCapacity(Int(symtab.numberOfSymbols))

    for i in 0..<symtab.numberOfSymbols {
      let offset = Int(symtab.symbolOffset) + Int(i) * Symbol.structSize

      // nlist_64 structure:
      // uint32_t n_strx (string table index)
      // uint8_t n_type
      // uint8_t n_sect
      // uint16_t n_desc
      // uint64_t n_value

      let strIndex = try reader.readUInt32(at: offset)
      let nType = try reader.readUInt8(at: offset + 4)
      let nSect = try reader.readUInt8(at: offset + 5)
      let nDesc = try reader.readUInt16(at: offset + 6)
      let nValue = try reader.readUInt64(at: offset + 8)

      let name = stringTable.string(at: strIndex)

      let symbol = Symbol(
        name: name,
        nType: nType,
        sectionIndex: nSect,
        description: nDesc,
        address: nValue
      )

      // Skip debug symbols for the main index
      if !symbol.isDebugSymbol {
        nameIndex[name] = symbols.count
      }

      symbols.append(symbol)
    }

    self.symbols = symbols
    self.nameIndex = nameIndex

    // Build address index with only defined, non-debug symbols
    self.addressIndex =
      symbols
      .filter { $0.isDefined && !$0.isDebugSymbol && $0.address > 0 }
      .sorted()
  }

  /// Number of symbols
  public var count: Int {
    symbols.count
  }

  /// Find a symbol by name
  /// - Parameter name: Symbol name to find
  /// - Returns: The symbol, or nil if not found
  public func symbol(named name: String) -> Symbol? {
    guard let index = nameIndex[name] else { return nil }
    return symbols[index]
  }

  /// Find a symbol at or before the given address
  /// - Parameter address: Address to search for
  /// - Returns: The symbol at that address, or nil if none found
  public func symbol(at address: UInt64) -> Symbol? {
    // Binary search for the address
    var low = 0
    var high = addressIndex.count - 1

    while low <= high {
      let mid = (low + high) / 2
      let symbol = addressIndex[mid]

      if symbol.address == address {
        return symbol
      } else if symbol.address < address {
        low = mid + 1
      } else {
        high = mid - 1
      }
    }

    // Return the symbol just before this address if any
    if high >= 0 {
      let symbol = addressIndex[high]
      // Only return if the address is reasonably close (within 64KB)
      if address - symbol.address < 0x10000 {
        return symbol
      }
    }

    return nil
  }

  /// Find the nearest symbol to an address
  /// - Parameter address: Address to search for
  /// - Returns: Tuple of (symbol, offset from symbol start), or nil if none found
  public func nearestSymbol(to address: UInt64) -> (symbol: Symbol, offset: UInt64)? {
    guard !addressIndex.isEmpty else { return nil }

    var low = 0
    var high = addressIndex.count - 1

    while low <= high {
      let mid = (low + high) / 2
      let symbol = addressIndex[mid]

      if symbol.address == address {
        return (symbol, 0)
      } else if symbol.address < address {
        low = mid + 1
      } else {
        high = mid - 1
      }
    }

    if high >= 0 {
      let symbol = addressIndex[high]
      return (symbol, address - symbol.address)
    }

    return nil
  }

  /// Get all external symbols
  public var externalSymbols: [Symbol] {
    symbols.filter { $0.isExternal && !$0.isDebugSymbol }
  }

  /// Get all defined symbols
  public var definedSymbols: [Symbol] {
    symbols.filter { $0.isDefined && !$0.isDebugSymbol }
  }

  /// Get all undefined symbols (imports)
  public var undefinedSymbols: [Symbol] {
    symbols.filter { !$0.isDefined && !$0.isDebugSymbol }
  }
}

// MARK: - Sequence Conformance

extension SymbolTable: Sequence {
  public func makeIterator() -> IndexingIterator<[Symbol]> {
    symbols.makeIterator()
  }
}
