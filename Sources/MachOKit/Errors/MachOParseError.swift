// MachOParseError.swift
// MachOKit
//
// Domain-specific parsing errors

import Foundation

/// Errors that can occur during Mach-O parsing
public enum MachOParseError: Error, Sendable {
  /// Invalid magic number
  case invalidMagic(found: UInt32, at: Int)

  /// File data is truncated
  case truncatedHeader(offset: Int, needed: Int, available: Int)

  /// Unsupported CPU type
  case unsupportedCPUType(Int32)

  /// Load command size mismatch
  case loadCommandSizeMismatch(expected: UInt32, actual: UInt32)

  /// Segment out of bounds
  case segmentOutOfBounds(name: String, offset: UInt64, size: UInt64)

  /// Section out of bounds
  case sectionOutOfBounds(name: String, offset: UInt32, size: UInt64)

  /// Invalid Fat binary magic
  case invalidFatMagic(found: UInt32)

  /// Empty Fat binary
  case emptyFatBinary

  /// Requested architecture not found in Fat binary
  case architectureNotFound(String)

  /// Invalid load command size
  case invalidLoadCommandSize(offset: Int, size: UInt32)

  /// Symbol not found
  case symbolNotFound(name: String)

  /// Insufficient data for read operation
  case insufficientData(offset: Int, needed: Int, available: Int)

  /// File not found
  case fileNotFound(path: String)

  /// File access error
  case fileAccessError(path: String, underlying: Error)

  /// Custom error with message
  case custom(message: String)

  /// Invalid code signature magic
  case invalidCodeSignatureMagic(expected: UInt32, found: UInt32, offset: Int)

  /// Invalid code signature length
  case invalidCodeSignatureLength(offset: Int, length: UInt32)

  /// Code signature not found
  case codeSignatureNotFound

  /// Invalid entitlements format
  case invalidEntitlementsFormat(reason: String)
}

extension MachOParseError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .invalidMagic(let found, let at):
      return "Invalid magic number 0x\(String(found, radix: 16)) at offset \(at)"
    case .truncatedHeader(let offset, let needed, let available):
      return
        "Truncated header at offset \(offset): needed \(needed) bytes, only \(available) available"
    case .unsupportedCPUType(let cpuType):
      return "Unsupported CPU type: \(cpuType)"
    case .loadCommandSizeMismatch(let expected, let actual):
      return "Load command size mismatch: expected \(expected), got \(actual)"
    case .segmentOutOfBounds(let name, let offset, let size):
      return "Segment '\(name)' out of bounds: offset \(offset), size \(size)"
    case .sectionOutOfBounds(let name, let offset, let size):
      return "Section '\(name)' out of bounds: offset \(offset), size \(size)"
    case .invalidFatMagic(let found):
      return "Invalid Fat binary magic: 0x\(String(found, radix: 16))"
    case .emptyFatBinary:
      return "Fat binary contains no architectures"
    case .architectureNotFound(let arch):
      return "Architecture '\(arch)' not found in Fat binary"
    case .invalidLoadCommandSize(let offset, let size):
      return "Invalid load command size \(size) at offset \(offset)"
    case .symbolNotFound(let name):
      return "Symbol '\(name)' not found"
    case .insufficientData(let offset, let needed, let available):
      return
        "Insufficient data at offset \(offset): needed \(needed) bytes, only \(available) available"
    case .fileNotFound(let path):
      return "File not found: \(path)"
    case .fileAccessError(let path, let underlying):
      return "Error accessing file '\(path)': \(underlying)"
    case .custom(let message):
      return message
    case .invalidCodeSignatureMagic(let expected, let found, let offset):
      return
        "Invalid code signature magic at offset \(offset): expected 0x\(String(expected, radix: 16)), found 0x\(String(found, radix: 16))"
    case .invalidCodeSignatureLength(let offset, let length):
      return "Invalid code signature length \(length) at offset \(offset)"
    case .codeSignatureNotFound:
      return "Code signature not found in binary"
    case .invalidEntitlementsFormat(let reason):
      return "Invalid entitlements format: \(reason)"
    }
  }
}
