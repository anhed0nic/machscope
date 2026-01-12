// DebuggerError.swift
// DebuggerCore
//
// Debugger-specific errors

import Foundation

/// Errors that can occur during debugging
public enum DebuggerError: Error, Sendable {
  /// Cannot attach to process
  case attachFailed(pid: Int32, reason: String)

  /// Permission denied
  case permissionDenied(operation: String, guidance: String)

  /// Missing debugger entitlement
  case missingDebuggerEntitlement(guidance: String)

  /// Developer Tools not enabled
  case developerToolsNotEnabled(guidance: String)

  /// SIP blocking operation
  case sipBlocking(path: String, guidance: String)

  /// Target lacks get-task-allow
  case targetLacksTaskAllow(pid: Int32)

  /// Invalid process ID
  case invalidPID(pid: Int32)

  /// Process not found
  case processNotFound(pid: Int32)

  /// Already attached
  case alreadyAttached(pid: Int32)

  /// Not attached
  case notAttached

  /// Invalid breakpoint address
  case invalidBreakpointAddress(address: UInt64)

  /// Breakpoint not found
  case breakpointNotFound(id: Int)

  /// Memory read failed
  case memoryReadFailed(address: UInt64, size: Int)

  /// Memory write failed
  case memoryWriteFailed(address: UInt64, size: Int)

  /// Thread operation failed
  case threadOperationFailed(operation: String)

  /// Timeout waiting for event
  case timeout(operation: String)
}

extension DebuggerError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .attachFailed(let pid, let reason):
      return "Cannot attach to process \(pid): \(reason)"
    case .permissionDenied(let operation, let guidance):
      return "Permission denied for '\(operation)'. \(guidance)"
    case .missingDebuggerEntitlement(let guidance):
      return "Missing debugger entitlement. \(guidance)"
    case .developerToolsNotEnabled(let guidance):
      return "Developer Tools not enabled. \(guidance)"
    case .sipBlocking(let path, let guidance):
      return "SIP blocks access to '\(path)'. \(guidance)"
    case .targetLacksTaskAllow(let pid):
      return "Target process \(pid) lacks get-task-allow entitlement"
    case .invalidPID(let pid):
      return "Invalid process ID: \(pid)"
    case .processNotFound(let pid):
      return "Process not found: \(pid)"
    case .alreadyAttached(let pid):
      return "Already attached to process \(pid)"
    case .notAttached:
      return "Not attached to any process"
    case .invalidBreakpointAddress(let address):
      return "Invalid breakpoint address: 0x\(String(address, radix: 16))"
    case .breakpointNotFound(let id):
      return "Breakpoint not found: \(id)"
    case .memoryReadFailed(let address, let size):
      return "Failed to read \(size) bytes at 0x\(String(address, radix: 16))"
    case .memoryWriteFailed(let address, let size):
      return "Failed to write \(size) bytes at 0x\(String(address, radix: 16))"
    case .threadOperationFailed(let operation):
      return "Thread operation failed: \(operation)"
    case .timeout(let operation):
      return "Timeout waiting for: \(operation)"
    }
  }
}

// MARK: - Exit Codes (per cli-interface.md)

extension DebuggerError {
  /// Exit code for CLI per cli-interface.md contract
  public var exitCode: Int32 {
    switch self {
    case .processNotFound:
      return 1
    case .permissionDenied, .missingDebuggerEntitlement:
      return 10
    case .sipBlocking:
      return 11
    case .targetLacksTaskAllow:
      return 12
    case .attachFailed:
      return 13
    default:
      return 1
    }
  }
}
