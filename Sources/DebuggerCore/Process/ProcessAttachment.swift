// ProcessAttachment.swift
// DebuggerCore
//
// Process attach/detach management

import Darwin
import Foundation

// Declare ptrace function (not available in Swift headers)
@_silgen_name("ptrace")
private func ptrace_call(
  _ request: Int32, _ pid: pid_t, _ addr: UnsafeMutableRawPointer?, _ data: Int32
) -> Int32

/// Process attachment state and management
///
/// Handles attaching to and detaching from a target process using ptrace
/// and Mach APIs. Provides a clean interface for debugger operations.
public final class ProcessAttachment: @unchecked Sendable {

  /// Process ID of the target
  public let pid: pid_t

  /// Task port for the target process
  public private(set) var taskPort: TaskPort?

  /// Whether currently attached
  public var isAttached: Bool {
    taskPort != nil && (taskPort?.isValid ?? false)
  }

  /// Process name (if available)
  public private(set) var processName: String?

  /// Attachment state
  public private(set) var state: AttachmentState = .detached

  // MARK: - Initialization

  /// Create an attachment manager for a process
  /// - Parameter pid: Process ID to attach to
  public init(pid: pid_t) {
    self.pid = pid
  }

  /// Create an attachment manager and immediately attach
  /// - Parameter pid: Process ID to attach to
  /// - Throws: DebuggerError if attachment fails
  public convenience init(attachingTo pid: pid_t) throws {
    self.init(pid: pid)
    try attach()
  }

  deinit {
    try? detach()
  }

  // MARK: - Attach/Detach

  /// Attach to the target process
  /// - Throws: DebuggerError if attachment fails
  public func attach() throws {
    guard !isAttached else {
      throw DebuggerError.alreadyAttached(pid: pid)
    }

    // Verify process exists
    guard kill(pid, 0) == 0 else {
      if errno == ESRCH {
        throw DebuggerError.processNotFound(pid: pid)
      }
      throw DebuggerError.permissionDenied(
        operation: "attach",
        guidance: "Cannot send signal to process \(pid)"
      )
    }

    // Get process name
    processName = Self.getProcessName(pid: pid)

    // Acquire task port
    taskPort = try TaskPort(pid: pid)

    // Use PT_ATTACHEXC to set up for Mach exception delivery
    // Note: ptrace is declared in sys/ptrace.h
    let PT_ATTACHEXC: Int32 = 14
    let result = ptrace_call(PT_ATTACHEXC, pid, nil, 0)
    if result != 0 {
      // ptrace failed but we have task port, continue anyway
      // Some operations work with just the task port
    }

    state = .stopped

    // Suspend the process initially
    try taskPort?.suspend()
    state = .stopped
  }

  /// Detach from the target process
  /// - Throws: DebuggerError if detach fails
  public func detach() throws {
    guard isAttached else {
      return  // Already detached, not an error
    }

    // Resume the process first
    if state == .stopped {
      try? taskPort?.resume()
    }

    // Detach using ptrace
    let PT_DETACH: Int32 = 17
    _ = ptrace_call(PT_DETACH, pid, nil, 0)

    // Clear task port
    taskPort = nil
    state = .detached
    processName = nil
  }

  // MARK: - Process Control

  /// Continue execution of the target process
  /// - Throws: DebuggerError if continue fails
  public func continueExecution() throws {
    guard isAttached else {
      throw DebuggerError.notAttached
    }

    try taskPort?.resume()
    state = .running
  }

  /// Stop (suspend) the target process
  /// - Throws: DebuggerError if stop fails
  public func stop() throws {
    guard isAttached else {
      throw DebuggerError.notAttached
    }

    try taskPort?.suspend()
    state = .stopped
  }

  /// Single step the main thread
  /// - Throws: DebuggerError if step fails
  #if arch(arm64)
    public func step() throws {
      guard isAttached else {
        throw DebuggerError.notAttached
      }

      guard let task = taskPort else {
        throw DebuggerError.notAttached
      }

      let mainThread = try task.mainThread()
      var threadState = try ThreadState.read(from: mainThread)
      try threadState.singleStep()

      // Resume and wait for single step exception
      state = .running
    }
  #endif

  // MARK: - Thread Access

  /// Get all threads in the target process
  /// - Returns: Array of ThreadState for all threads
  /// - Throws: DebuggerError if thread enumeration fails
  #if arch(arm64)
    public func threads() throws -> [ThreadState] {
      guard let task = taskPort else {
        throw DebuggerError.notAttached
      }

      let threadPorts = try task.threads()
      return try threadPorts.map { thread in
        try ThreadState.read(from: thread)
      }
    }

    /// Get the main thread state
    /// - Returns: ThreadState for the main thread
    /// - Throws: DebuggerError if reading fails
    public func mainThread() throws -> ThreadState {
      guard let task = taskPort else {
        throw DebuggerError.notAttached
      }

      let thread = try task.mainThread()
      return try ThreadState.read(from: thread)
    }
  #endif

  // MARK: - Memory Access

  /// Get a memory reader for this process
  /// - Returns: MemoryReader instance
  /// - Throws: DebuggerError if not attached
  public func memoryReader() throws -> MemoryReader {
    guard let task = taskPort else {
      throw DebuggerError.notAttached
    }
    return MemoryReader(task: task)
  }

  /// Get a memory writer for this process
  /// - Returns: MemoryWriter instance
  /// - Throws: DebuggerError if not attached
  public func memoryWriter() throws -> MemoryWriter {
    guard let task = taskPort else {
      throw DebuggerError.notAttached
    }
    return MemoryWriter(task: task)
  }

  // MARK: - Process Info

  /// Get basic process info
  /// - Returns: ProcessBasicInfo
  /// - Throws: DebuggerError if reading fails
  public func processInfo() throws -> ProcessBasicInfo {
    guard let task = taskPort else {
      throw DebuggerError.notAttached
    }
    return try task.processInfo()
  }

  // MARK: - Helpers

  /// Get process name by PID
  private static func getProcessName(pid: pid_t) -> String? {
    var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    let result = proc_pidpath(pid, &buffer, UInt32(buffer.count))

    if result > 0 {
      let path = String(cString: buffer)
      return (path as NSString).lastPathComponent
    }

    return nil
  }
}

// MARK: - Attachment State

/// State of the process attachment
public enum AttachmentState: Sendable {
  /// Not attached to any process
  case detached

  /// Attached and process is stopped
  case stopped

  /// Attached and process is running
  case running

  /// Attached and process is at a breakpoint
  case breakpoint
}

// MARK: - Debug Description

extension ProcessAttachment: CustomDebugStringConvertible {
  public var debugDescription: String {
    let name = processName ?? "unknown"
    return "ProcessAttachment(pid: \(pid), name: \(name), state: \(state))"
  }
}

// MARK: - External C Function Declaration

// proc_pidpath is in libproc
@_silgen_name("proc_pidpath")
private func proc_pidpath(_ pid: pid_t, _ buffer: UnsafeMutablePointer<CChar>, _ bufferSize: UInt32)
  -> Int32
