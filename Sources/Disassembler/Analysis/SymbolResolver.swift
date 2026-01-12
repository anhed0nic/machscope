// SymbolResolver.swift
// Disassembler
//
// Symbol resolution protocol and implementation

import Foundation
import MachOKit

/// Protocol for symbol resolution
public protocol SymbolResolving: Sendable {
  /// Resolve a symbol at the given address
  func symbol(at address: UInt64) -> String?
}

/// Default symbol resolver (returns nil)
public struct SymbolResolver: SymbolResolving, Sendable {
  public init() {}

  public func symbol(at address: UInt64) -> String? {
    nil
  }
}

/// Symbol resolver backed by MachOBinary
public struct MachOSymbolResolver: SymbolResolving, Sendable {
  private let binary: MachOBinary

  public init(binary: MachOBinary) {
    self.binary = binary
  }

  public func symbol(at address: UInt64) -> String? {
    binary.symbol(at: address)?.name
  }

  /// Find a symbol by name
  public func symbol(named name: String) -> Symbol? {
    binary.symbol(named: name)
  }
}

/// Symbol table for fast address lookups
public struct SymbolLookupTable: SymbolResolving, Sendable {
  private let addressToSymbol: [UInt64: String]

  public init(symbols: [Symbol]) {
    var table: [UInt64: String] = [:]
    for symbol in symbols {
      table[symbol.address] = symbol.name
    }
    self.addressToSymbol = table
  }

  public init(symbols: [(address: UInt64, name: String)]) {
    var table: [UInt64: String] = [:]
    for symbol in symbols {
      table[symbol.address] = symbol.name
    }
    self.addressToSymbol = table
  }

  public func symbol(at address: UInt64) -> String? {
    addressToSymbol[address]
  }
}
