// DisassemblyError.swift
// Disassembler
//
// Disassembly-specific errors

import Foundation

/// Errors that can occur during disassembly
public enum DisassemblyError: Error, Sendable {
  /// Truncated instruction
  case truncatedInstruction(address: UInt64, needed: Int, available: Int)

  /// Invalid instruction encoding
  case invalidEncoding(address: UInt64, encoding: UInt32)

  /// Address not in executable segment
  case addressNotExecutable(address: UInt64)

  /// Symbol not found
  case symbolNotFound(name: String)

  /// Function boundaries not found
  case functionBoundariesNotFound(address: UInt64)

  /// Insufficient data to decode instruction
  case insufficientData(expected: Int, actual: Int)

  /// Invalid alignment for instruction
  case invalidAlignment(address: UInt64, required: Int)

  /// Section not found
  case sectionNotFound(name: String)

  /// Address out of range
  case addressOutOfRange(address: UInt64, validRange: Range<UInt64>)

  /// Invalid address range
  case invalidAddressRange(start: UInt64, end: UInt64)
}

extension DisassemblyError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .truncatedInstruction(let address, let needed, let available):
      return
        "Truncated instruction at 0x\(String(address, radix: 16)): needed \(needed) bytes, only \(available) available"
    case .invalidEncoding(let address, let encoding):
      return
        "Invalid instruction encoding at 0x\(String(address, radix: 16)): 0x\(String(encoding, radix: 16))"
    case .addressNotExecutable(let address):
      return "Address 0x\(String(address, radix: 16)) is not in an executable segment"
    case .symbolNotFound(let name):
      return "Symbol not found: \(name)"
    case .functionBoundariesNotFound(let address):
      return "Cannot determine function boundaries at 0x\(String(address, radix: 16))"
    case .insufficientData(let expected, let actual):
      return "Insufficient data: expected \(expected) bytes, got \(actual)"
    case .invalidAlignment(let address, let required):
      return
        "Invalid alignment at 0x\(String(address, radix: 16)): must be \(required)-byte aligned"
    case .sectionNotFound(let name):
      return "Section not found: \(name)"
    case .addressOutOfRange(let address, let validRange):
      return
        "Address 0x\(String(address, radix: 16)) out of range (0x\(String(validRange.lowerBound, radix: 16))-0x\(String(validRange.upperBound, radix: 16)))"
    case .invalidAddressRange(let start, let end):
      return "Invalid address range: 0x\(String(start, radix: 16)) to 0x\(String(end, radix: 16))"
    }
  }
}
