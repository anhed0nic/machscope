// MachExceptionServer.swift
// DebuggerCore
//
// Exception port server

import Darwin
import Foundation

/// Mach exception server
///
/// Sets up and manages exception ports for receiving Mach exceptions
/// from the target process. This is the primary mechanism for receiving
/// breakpoint and crash notifications on macOS.
public final class MachExceptionServer: @unchecked Sendable {

  /// Task port for the target process
  private let taskPort: mach_port_t

  /// Exception port for receiving exceptions
  private var exceptionPort: mach_port_t = 0

  /// Original exception ports (saved for restoration)
  private var savedPorts: SavedExceptionPorts?

  /// Whether the server is running
  public private(set) var isRunning: Bool = false

  /// Exception handler
  private let handler: ExceptionHandler

  /// Lock for thread safety
  private let lock = NSLock()

  // MARK: - Initialization

  /// Create an exception server for a task
  /// - Parameters:
  ///   - taskPort: Task port for the target process
  ///   - handler: Exception handler for processing events
  public init(taskPort: mach_port_t, handler: ExceptionHandler = ExceptionHandler()) {
    self.taskPort = taskPort
    self.handler = handler
  }

  deinit {
    stop()
  }

  // MARK: - Server Control

  /// Start the exception server
  /// - Throws: DebuggerError if server cannot be started
  public func start() throws {
    lock.lock()
    defer { lock.unlock() }

    guard !isRunning else {
      return  // Already running
    }

    // Allocate exception port
    var port: mach_port_t = 0
    var kr = mach_port_allocate(
      mach_task_self_,
      MACH_PORT_RIGHT_RECEIVE,
      &port
    )

    guard kr == KERN_SUCCESS else {
      throw DebuggerError.threadOperationFailed(operation: "allocate exception port")
    }

    // Add send right
    kr = mach_port_insert_right(
      mach_task_self_,
      port,
      port,
      mach_msg_type_name_t(MACH_MSG_TYPE_MAKE_SEND)
    )

    guard kr == KERN_SUCCESS else {
      mach_port_deallocate(mach_task_self_, port)
      throw DebuggerError.threadOperationFailed(operation: "insert port right")
    }

    exceptionPort = port

    // Save current exception ports
    savedPorts = try saveExceptionPorts()

    // Set our exception port on the target task
    // EXC_MASK_ALL covers all standard exceptions
    let EXC_MASK_ALL: exception_mask_t = 0x3ffe  // All exception masks combined
    kr = task_set_exception_ports(
      taskPort,
      EXC_MASK_ALL,
      exceptionPort,
      exception_behavior_t(EXCEPTION_DEFAULT) | exception_behavior_t(MACH_EXCEPTION_CODES),
      ARM_THREAD_STATE64
    )

    guard kr == KERN_SUCCESS else {
      mach_port_deallocate(mach_task_self_, port)
      exceptionPort = 0
      throw DebuggerError.threadOperationFailed(operation: "set exception ports")
    }

    isRunning = true
  }

  /// Stop the exception server
  public func stop() {
    lock.lock()
    defer { lock.unlock() }

    guard isRunning else {
      return
    }

    // Restore original exception ports
    if let saved = savedPorts {
      restoreExceptionPorts(saved)
    }

    // Deallocate our exception port
    if exceptionPort != 0 {
      mach_port_deallocate(mach_task_self_, exceptionPort)
      exceptionPort = 0
    }

    isRunning = false
    savedPorts = nil
  }

  // MARK: - Exception Waiting

  /// Wait for an exception event
  /// - Parameter timeout: Timeout in milliseconds (0 for infinite)
  /// - Returns: Exception event, or nil on timeout
  /// - Throws: DebuggerError if waiting fails
  public func waitForException(timeout: UInt32 = 0) throws -> ExceptionEvent? {
    guard isRunning else {
      throw DebuggerError.notAttached
    }

    // Set up message buffer
    let bufferSize = 1024
    var buffer = [UInt8](repeating: 0, count: bufferSize)

    let options =
      timeout > 0
      ? MACH_RCV_MSG | MACH_RCV_TIMEOUT
      : MACH_RCV_MSG

    let kr = buffer.withUnsafeMutableBytes { bufferPtr in
      mach_msg(
        bufferPtr.baseAddress!.assumingMemoryBound(to: mach_msg_header_t.self),
        Int32(options),
        0,
        mach_msg_size_t(bufferSize),
        exceptionPort,
        timeout,
        mach_port_name_t(MACH_PORT_NULL)
      )
    }

    if kr == MACH_RCV_TIMED_OUT {
      return nil  // Timeout, no exception
    }

    guard kr == KERN_SUCCESS else {
      throw DebuggerError.timeout(operation: "wait for exception")
    }

    // Parse the exception message
    return parseExceptionMessage(buffer)
  }

  // MARK: - Message Parsing

  /// Parse an exception message into an event
  private func parseExceptionMessage(_ buffer: [UInt8]) -> ExceptionEvent? {
    // The message structure depends on the exception type
    // This is a simplified implementation

    guard buffer.count >= MemoryLayout<mach_msg_header_t>.size else {
      return nil
    }

    // Extract header
    let header = buffer.withUnsafeBytes { ptr in
      ptr.load(as: mach_msg_header_t.self)
    }

    // For now, return a basic exception event
    // A full implementation would parse the complete exception message

    let event = ExceptionEvent(
      thread: mach_port_t(MACH_PORT_NULL),
      task: taskPort,
      exceptionType: .breakpoint,
      codes: []
    )

    return event
  }

  // MARK: - Exception Port Management

  /// Saved exception ports structure
  private struct SavedExceptionPorts {
    var masks: [exception_mask_t]
    var ports: [mach_port_t]
    var behaviors: [exception_behavior_t]
    var flavors: [thread_state_flavor_t]
    var count: mach_msg_type_number_t
  }

  /// Save current exception ports
  private func saveExceptionPorts() throws -> SavedExceptionPorts {
    let EXC_TYPES_COUNT_LOCAL = 14  // Number of exception types
    var masks = [exception_mask_t](repeating: 0, count: EXC_TYPES_COUNT_LOCAL)
    var ports = [mach_port_t](repeating: 0, count: EXC_TYPES_COUNT_LOCAL)
    var behaviors = [exception_behavior_t](repeating: 0, count: EXC_TYPES_COUNT_LOCAL)
    var flavors = [thread_state_flavor_t](repeating: 0, count: EXC_TYPES_COUNT_LOCAL)
    var count = mach_msg_type_number_t(EXC_TYPES_COUNT_LOCAL)

    let EXC_MASK_ALL_LOCAL: exception_mask_t = 0x3ffe
    let kr = task_get_exception_ports(
      taskPort,
      EXC_MASK_ALL_LOCAL,
      &masks,
      &count,
      &ports,
      &behaviors,
      &flavors
    )

    guard kr == KERN_SUCCESS else {
      throw DebuggerError.threadOperationFailed(operation: "get exception ports")
    }

    return SavedExceptionPorts(
      masks: masks,
      ports: ports,
      behaviors: behaviors,
      flavors: flavors,
      count: count
    )
  }

  /// Restore saved exception ports
  private func restoreExceptionPorts(_ saved: SavedExceptionPorts) {
    for i in 0..<Int(saved.count) {
      if saved.masks[i] != 0 && saved.ports[i] != MACH_PORT_NULL {
        task_set_exception_ports(
          taskPort,
          saved.masks[i],
          saved.ports[i],
          saved.behaviors[i],
          saved.flavors[i]
        )
      }
    }
  }
}

// MARK: - Debug Description

extension MachExceptionServer: CustomDebugStringConvertible {
  public var debugDescription: String {
    "MachExceptionServer(running: \(isRunning), port: \(exceptionPort))"
  }
}
