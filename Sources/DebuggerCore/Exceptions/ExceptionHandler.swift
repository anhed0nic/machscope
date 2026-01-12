// ExceptionHandler.swift
// DebuggerCore
//
// Mach exception handler

import Darwin
import Foundation

/// Exception type enumeration
public enum ExceptionType: Int32, Sendable {
  /// Bad memory access (e.g., NULL pointer)
  case badAccess = 1

  /// Bad instruction (e.g., illegal opcode)
  case badInstruction = 2

  /// Arithmetic exception (e.g., divide by zero)
  case arithmetic = 3

  /// Emulation (obsolete)
  case emulation = 4

  /// Software exception (e.g., breakpoint)
  case software = 5

  /// Breakpoint
  case breakpoint = 6

  /// System call
  case syscall = 7

  /// Mach system call
  case machSyscall = 8

  /// RPC alert
  case rpcAlert = 9

  /// Crash
  case crash = 10

  /// Resource protection
  case resource = 11

  /// Guard exception
  case guardException = 12

  /// Corpse notification
  case corpseNotify = 13

  /// Unknown exception
  case unknown = -1

  /// Create from raw exception type
  public init(rawException: Int32) {
    self = ExceptionType(rawValue: rawException) ?? .unknown
  }

  /// Human-readable description
  public var description: String {
    switch self {
    case .badAccess: return "EXC_BAD_ACCESS"
    case .badInstruction: return "EXC_BAD_INSTRUCTION"
    case .arithmetic: return "EXC_ARITHMETIC"
    case .emulation: return "EXC_EMULATION"
    case .software: return "EXC_SOFTWARE"
    case .breakpoint: return "EXC_BREAKPOINT"
    case .syscall: return "EXC_SYSCALL"
    case .machSyscall: return "EXC_MACH_SYSCALL"
    case .rpcAlert: return "EXC_RPC_ALERT"
    case .crash: return "EXC_CRASH"
    case .resource: return "EXC_RESOURCE"
    case .guardException: return "EXC_GUARD"
    case .corpseNotify: return "EXC_CORPSE_NOTIFY"
    case .unknown: return "EXC_UNKNOWN"
    }
  }
}

/// Exception event from the target process
public struct ExceptionEvent: Sendable {
  /// Thread that raised the exception
  public let thread: thread_t

  /// Task that raised the exception
  public let task: mach_port_t

  /// Exception type
  public let exceptionType: ExceptionType

  /// Exception codes (meaning depends on type)
  public let codes: [UInt64]

  /// Whether this is a breakpoint exception
  public var isBreakpoint: Bool {
    exceptionType == .breakpoint || exceptionType == .software
  }

  /// Whether this is a single step exception
  public var isSingleStep: Bool {
    // On ARM64, single step is delivered as EXC_BREAKPOINT with specific codes
    exceptionType == .breakpoint && codes.count >= 2 && codes[0] == 1
  }

  /// Address that caused the exception (if applicable)
  public var faultAddress: UInt64? {
    guard exceptionType == .badAccess, codes.count >= 2 else {
      return nil
    }
    return codes[1]
  }

  // MARK: - Initialization

  public init(
    thread: thread_t,
    task: mach_port_t,
    exceptionType: ExceptionType,
    codes: [UInt64]
  ) {
    self.thread = thread
    self.task = task
    self.exceptionType = exceptionType
    self.codes = codes
  }
}

// MARK: - CustomStringConvertible

extension ExceptionEvent: CustomStringConvertible {
  public var description: String {
    var desc = "\(exceptionType.description)"
    if !codes.isEmpty {
      let codeStrings = codes.map { "0x\(String($0, radix: 16))" }
      desc += " codes=[\(codeStrings.joined(separator: ", "))]"
    }
    return desc
  }
}

/// Mach exception handler
///
/// Handles Mach exceptions from the target process, including breakpoints
/// and single step events.
public struct ExceptionHandler: Sendable {

  /// Callback type for exception events
  public typealias ExceptionCallback = @Sendable (ExceptionEvent) -> ExceptionResponse

  /// Response to an exception
  public enum ExceptionResponse: Sendable {
    /// Continue execution normally
    case continueExecution

    /// Stop execution (debugger should handle)
    case stopExecution

    /// Deliver exception to default handler (will likely crash)
    case deliverToDefault

    /// Single step and continue
    case singleStep
  }

  // MARK: - Initialization

  public init() {}

  // MARK: - Exception Handling

  /// Handle a breakpoint exception
  /// - Parameter event: The exception event
  /// - Returns: Response indicating how to handle it
  public func handleBreakpoint(event: ExceptionEvent) -> ExceptionResponse {
    // Breakpoints should stop execution for debugger handling
    return .stopExecution
  }

  /// Handle a single step exception
  /// - Parameter event: The exception event
  /// - Returns: Response indicating how to handle it
  public func handleSingleStep(event: ExceptionEvent) -> ExceptionResponse {
    // Single step should stop for debugger to inspect state
    return .stopExecution
  }

  /// Handle a bad access exception
  /// - Parameter event: The exception event
  /// - Returns: Response indicating how to handle it
  public func handleBadAccess(event: ExceptionEvent) -> ExceptionResponse {
    // Bad access (segfault) should stop for inspection
    return .stopExecution
  }

  /// Handle any exception
  /// - Parameter event: The exception event
  /// - Returns: Response indicating how to handle it
  public func handle(event: ExceptionEvent) -> ExceptionResponse {
    switch event.exceptionType {
    case .breakpoint:
      if event.isSingleStep {
        return handleSingleStep(event: event)
      }
      return handleBreakpoint(event: event)

    case .software:
      // Software exceptions include breakpoints
      return handleBreakpoint(event: event)

    case .badAccess:
      return handleBadAccess(event: event)

    case .badInstruction:
      return .stopExecution

    case .arithmetic:
      return .stopExecution

    default:
      // For other exceptions, stop for inspection
      return .stopExecution
    }
  }

  // MARK: - Exception Info Formatting

  /// Format exception details for display
  /// - Parameter event: The exception event
  /// - Returns: Human-readable description
  public func formatException(event: ExceptionEvent) -> String {
    var lines: [String] = []

    lines.append("Exception: \(event.exceptionType.description)")
    lines.append("Thread: \(event.thread)")

    if !event.codes.isEmpty {
      let codeStrings = event.codes.map { "0x\(String($0, radix: 16))" }
      lines.append("Codes: [\(codeStrings.joined(separator: ", "))]")
    }

    if let faultAddr = event.faultAddress {
      lines.append("Fault Address: 0x\(String(faultAddr, radix: 16))")
    }

    if event.isBreakpoint {
      lines.append("Type: Breakpoint")
    } else if event.isSingleStep {
      lines.append("Type: Single Step")
    }

    return lines.joined(separator: "\n")
  }
}
