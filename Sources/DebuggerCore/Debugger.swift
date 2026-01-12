// Debugger.swift
// DebuggerCore
//
// Main entry point for process debugging

import Darwin
import Disassembler
import Foundation
import MachOKit

/// Debugger state
public enum DebuggerState: Sendable {
  /// Not attached to any process
  case detached

  /// Attached and process is stopped
  case stopped

  /// Attached and process is running
  case running

  /// At a breakpoint
  case atBreakpoint(address: UInt64, symbol: String?)

  /// Single stepped
  case stepped
}

/// Stop reason for the debugger
public enum StopReason: Sendable {
  /// User requested stop
  case userRequest

  /// Hit a breakpoint
  case breakpoint(id: Int, address: UInt64)

  /// Completed single step
  case step

  /// Exception occurred
  case exception(type: ExceptionType)

  /// Process exited
  case exited(code: Int32)

  /// Unknown reason
  case unknown
}

/// Main debugger class
///
/// Provides a high-level interface for debugging processes on macOS.
/// Integrates process attachment, breakpoints, memory access, and
/// exception handling into a cohesive debugging experience.
public final class Debugger: @unchecked Sendable {

  /// Process attachment manager
  private var attachment: ProcessAttachment?

  /// Breakpoint manager
  private let breakpointManager = BreakpointManager()

  /// Exception handler
  private let exceptionHandler = ExceptionHandler()

  /// Permission checker
  private let permissionChecker = PermissionChecker()

  /// Current debugger state
  public private(set) var state: DebuggerState = .detached

  /// Last stop reason
  public private(set) var lastStopReason: StopReason = .unknown

  /// Process ID of attached process
  public var pid: pid_t? {
    attachment?.pid
  }

  /// Process name of attached process
  public var processName: String? {
    attachment?.processName
  }

  /// Whether attached to a process
  public var isAttached: Bool {
    attachment?.isAttached ?? false
  }

  // MARK: - Initialization

  public init() {}

  // MARK: - Attach/Detach

  /// Attach to a process by PID
  /// - Parameter pid: Process ID to attach to
  /// - Throws: DebuggerError if attachment fails
  public func attach(to pid: pid_t) throws {
    // Check permissions first
    guard permissionChecker.canDebug else {
      let status = permissionChecker.status
      if !status.developerToolsEnabled {
        throw DebuggerError.developerToolsNotEnabled(
          guidance: permissionChecker.guidanceFor(permission: "developertools")
        )
      }
      if !status.debuggerEntitlement {
        throw DebuggerError.missingDebuggerEntitlement(
          guidance: permissionChecker.guidanceFor(permission: "entitlement")
        )
      }
      throw DebuggerError.permissionDenied(
        operation: "attach",
        guidance: permissionChecker.guidance
      )
    }

    // Detach from current process if attached
    if isAttached {
      try detach()
    }

    // Create new attachment
    let newAttachment = ProcessAttachment(pid: pid)
    try newAttachment.attach()

    attachment = newAttachment
    state = .stopped
    lastStopReason = .userRequest
  }

  /// Detach from the current process
  /// - Throws: DebuggerError if detach fails
  public func detach() throws {
    guard let attachment = attachment else {
      return  // Already detached
    }

    // Remove all breakpoints from memory
    for bp in breakpointManager.enabledBreakpoints {
      try? restoreOriginalInstruction(at: bp.address)
    }
    breakpointManager.clearAll()

    try attachment.detach()
    self.attachment = nil
    state = .detached
  }

  // MARK: - Execution Control

  /// Continue execution
  /// - Throws: DebuggerError if continue fails
  public func continueExecution() throws {
    guard let attachment = attachment else {
      throw DebuggerError.notAttached
    }

    // If at breakpoint, single step over it first
    if case .atBreakpoint(let address, _) = state {
      try stepOverBreakpoint(at: address)
    }

    try attachment.continueExecution()
    state = .running
  }

  /// Stop execution
  /// - Throws: DebuggerError if stop fails
  public func stop() throws {
    guard let attachment = attachment else {
      throw DebuggerError.notAttached
    }

    try attachment.stop()
    state = .stopped
    lastStopReason = .userRequest
  }

  /// Single step one instruction
  /// - Throws: DebuggerError if step fails
  #if arch(arm64)
    public func step() throws {
      guard let attachment = attachment else {
        throw DebuggerError.notAttached
      }

      // If at breakpoint, step over it
      if case .atBreakpoint(let address, _) = state {
        try stepOverBreakpoint(at: address)
      }

      try attachment.step()
      state = .stepped
      lastStopReason = .step
    }
  #endif

  // MARK: - Breakpoints

  /// Set a breakpoint at an address
  /// - Parameters:
  ///   - address: Address for the breakpoint
  ///   - symbol: Optional symbol name
  /// - Returns: Breakpoint ID
  /// - Throws: DebuggerError if breakpoint cannot be set
  @discardableResult
  public func setBreakpoint(at address: UInt64, symbol: String? = nil) throws -> Int {
    guard let attachment = attachment else {
      throw DebuggerError.notAttached
    }

    // Read original instruction
    let reader = try attachment.memoryReader()
    let originalInstruction = try reader.readUInt32(at: address)

    // Add to breakpoint manager
    let id = try breakpointManager.addBreakpoint(
      at: address,
      symbol: symbol,
      originalBytes: originalInstruction
    )

    // Write breakpoint instruction
    let writer = try attachment.memoryWriter()
    try writer.writeInstructionWithProtectionChange(
      ARM64BreakpointInstruction.brk0,
      at: address
    )

    return id
  }

  /// Remove a breakpoint
  /// - Parameter id: Breakpoint ID to remove
  /// - Throws: DebuggerError if breakpoint cannot be removed
  public func removeBreakpoint(id: Int) throws {
    guard let bp = breakpointManager.breakpoint(id: id) else {
      throw DebuggerError.breakpointNotFound(id: id)
    }

    // Restore original instruction
    try restoreOriginalInstruction(at: bp.address)

    // Remove from manager
    try breakpointManager.removeBreakpoint(id: id)
  }

  /// Get all breakpoints
  public var breakpoints: [Breakpoint] {
    breakpointManager.breakpoints
  }

  /// Get breakpoint by ID
  public func breakpoint(id: Int) -> Breakpoint? {
    breakpointManager.breakpoint(id: id)
  }

  // MARK: - Registers

  /// Get current register state
  /// - Returns: ARM64 registers
  /// - Throws: DebuggerError if reading fails
  #if arch(arm64)
    public func registers() throws -> ARM64Registers {
      guard let attachment = attachment else {
        throw DebuggerError.notAttached
      }

      let thread = try attachment.mainThread()
      return thread.registers
    }
  #endif

  /// Get program counter
  /// - Returns: Current PC value
  /// - Throws: DebuggerError if reading fails
  #if arch(arm64)
    public func programCounter() throws -> UInt64 {
      try registers().pc
    }
  #endif

  // MARK: - Memory

  /// Read memory from the target process
  /// - Parameters:
  ///   - address: Address to read from
  ///   - size: Number of bytes to read
  /// - Returns: Data read from memory
  /// - Throws: DebuggerError if read fails
  public func readMemory(at address: UInt64, size: Int) throws -> Data {
    guard let attachment = attachment else {
      throw DebuggerError.notAttached
    }

    let reader = try attachment.memoryReader()
    return try reader.read(at: address, size: size)
  }

  /// Write memory to the target process
  /// - Parameters:
  ///   - data: Data to write
  ///   - address: Address to write to
  /// - Throws: DebuggerError if write fails
  public func writeMemory(_ data: Data, at address: UInt64) throws {
    guard let attachment = attachment else {
      throw DebuggerError.notAttached
    }

    let writer = try attachment.memoryWriter()
    try writer.write(data, at: address)
  }

  /// Examine memory (similar to gdb's x command)
  /// - Parameters:
  ///   - address: Starting address
  ///   - count: Number of units
  ///   - format: Format (b=byte, h=halfword, w=word, g=giant/64-bit)
  /// - Returns: Formatted memory dump
  /// - Throws: DebuggerError if read fails
  public func examineMemory(
    at address: UInt64,
    count: Int,
    format: Character = "w"
  ) throws -> String {
    let unitSize: Int
    switch format {
    case "b": unitSize = 1
    case "h": unitSize = 2
    case "w": unitSize = 4
    case "g": unitSize = 8
    default: unitSize = 4
    }

    let data = try readMemory(at: address, size: count * unitSize)
    var output: [String] = []
    var currentLine = "0x\(String(address, radix: 16)): "
    var lineItems = 0

    for i in stride(from: 0, to: data.count, by: unitSize) {
      let value: UInt64
      switch unitSize {
      case 1:
        value = UInt64(data[i])
      case 2:
        value = data.withUnsafeBytes { ptr in
          UInt64(ptr.load(fromByteOffset: i, as: UInt16.self))
        }
      case 4:
        value = data.withUnsafeBytes { ptr in
          UInt64(ptr.load(fromByteOffset: i, as: UInt32.self))
        }
      case 8:
        value = data.withUnsafeBytes { ptr in
          ptr.load(fromByteOffset: i, as: UInt64.self)
        }
      default:
        value = 0
      }

      let hexValue = "0x\(String(value, radix: 16))"
      currentLine += "\(hexValue) "
      lineItems += 1

      if lineItems >= 4 {
        output.append(currentLine)
        let nextAddr = address + UInt64(i + unitSize)
        currentLine = "0x\(String(nextAddr, radix: 16)): "
        lineItems = 0
      }
    }

    if lineItems > 0 {
      output.append(currentLine)
    }

    return output.joined(separator: "\n")
  }

  // MARK: - Disassembly

  /// Disassemble instructions at an address
  /// - Parameters:
  ///   - address: Starting address
  ///   - count: Number of instructions
  /// - Returns: Formatted disassembly
  /// - Throws: DebuggerError if disassembly fails
  public func disassemble(at address: UInt64, count: Int) throws -> String {
    guard let attachment = attachment else {
      throw DebuggerError.notAttached
    }

    let reader = try attachment.memoryReader()
    let instructions = try reader.readInstructions(at: address, count: count)

    let disassembler = ARM64Disassembler()
    var output: [String] = []

    for (index, encoding) in instructions.enumerated() {
      let addr = address + UInt64(index * 4)
      let instruction = disassembler.decode(encoding, at: addr)
      let formatted = disassembler.format(instruction)
      output.append("0x\(String(addr, radix: 16)):  \(formatted)")
    }

    return output.joined(separator: "\n")
  }

  // MARK: - Process Info

  /// Get process information
  /// - Returns: Process basic info
  /// - Throws: DebuggerError if reading fails
  public func processInfo() throws -> ProcessBasicInfo {
    guard let attachment = attachment else {
      throw DebuggerError.notAttached
    }

    return try attachment.processInfo()
  }

  // MARK: - Internal Helpers

  /// Restore original instruction at an address
  private func restoreOriginalInstruction(at address: UInt64) throws {
    guard let bp = breakpointManager.breakpoint(at: address),
      let attachment = attachment
    else {
      return
    }

    let writer = try attachment.memoryWriter()
    try writer.writeInstructionWithProtectionChange(bp.originalBytes, at: address)
  }

  /// Step over a breakpoint
  private func stepOverBreakpoint(at address: UInt64) throws {
    guard let bp = breakpointManager.breakpoint(at: address) else {
      return
    }

    // Restore original instruction
    try restoreOriginalInstruction(at: address)

    // Single step
    #if arch(arm64)
      try attachment?.step()
    #endif

    // Re-insert breakpoint if still enabled
    if bp.isEnabled, let attachment = attachment {
      let writer = try attachment.memoryWriter()
      try writer.writeInstructionWithProtectionChange(
        ARM64BreakpointInstruction.brk0,
        at: address
      )
    }
  }
}

// MARK: - CustomDebugStringConvertible

extension Debugger: CustomDebugStringConvertible {
  public var debugDescription: String {
    if let pid = pid, let name = processName {
      return "Debugger(pid: \(pid), name: \(name), state: \(state))"
    }
    return "Debugger(detached)"
  }
}
