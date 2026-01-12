// TaskPort.swift
// DebuggerCore
//
// task_for_pid wrapper

import Darwin
import Foundation

/// Wrapper for Mach task port
///
/// Provides safe access to a target process's task port, which is required
/// for memory access, thread enumeration, and debugging operations.
public final class TaskPort: @unchecked Sendable {

  /// The process ID this task port belongs to
  public let pid: pid_t

  /// The underlying Mach task port
  private var _port: mach_port_t

  /// Access to the underlying port (read-only)
  public var port: mach_port_t { _port }

  /// Whether this task port is valid
  public var isValid: Bool {
    _port != mach_port_t(MACH_PORT_NULL) && _port != UInt32.max  // MACH_PORT_DEAD = ~0 = UInt32.max
  }

  // MARK: - Initialization

  /// Create a TaskPort by acquiring task_for_pid
  /// - Parameter pid: Process ID to get task port for
  /// - Throws: DebuggerError if task_for_pid fails
  public init(pid: pid_t) throws {
    guard pid > 0 else {
      throw DebuggerError.invalidPID(pid: pid)
    }

    self.pid = pid
    self._port = mach_port_t(MACH_PORT_NULL)

    var task: mach_port_t = mach_port_t(MACH_PORT_NULL)
    let kr = task_for_pid(mach_task_self_, pid, &task)

    guard kr == KERN_SUCCESS else {
      throw TaskPort.mapKernelError(kr, pid: pid)
    }

    self._port = task
  }

  /// Create a TaskPort from an existing port (for testing)
  internal init(pid: pid_t, existingPort: mach_port_t) {
    self.pid = pid
    self._port = existingPort
  }

  deinit {
    if isValid {
      mach_port_deallocate(mach_task_self_, _port)
    }
  }

  // MARK: - Thread Enumeration

  /// Get all threads in the target process
  /// - Returns: Array of thread ports
  /// - Throws: DebuggerError if thread enumeration fails
  public func threads() throws -> [thread_t] {
    guard isValid else {
      throw DebuggerError.notAttached
    }

    var threadList: thread_act_array_t?
    var threadCount: mach_msg_type_number_t = 0

    let kr = task_threads(_port, &threadList, &threadCount)
    guard kr == KERN_SUCCESS else {
      throw DebuggerError.threadOperationFailed(operation: "enumerate threads")
    }

    defer {
      // Deallocate the thread list memory
      if let list = threadList {
        let size = vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_t>.size)
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: list), size)
      }
    }

    guard let list = threadList else {
      return []
    }

    return Array(UnsafeBufferPointer(start: list, count: Int(threadCount)))
  }

  /// Get the main thread (first thread)
  /// - Returns: Main thread port
  /// - Throws: DebuggerError if no threads found
  public func mainThread() throws -> thread_t {
    let allThreads = try threads()
    guard let main = allThreads.first else {
      throw DebuggerError.threadOperationFailed(operation: "get main thread")
    }
    return main
  }

  // MARK: - Process Info

  /// Get basic info about the target process
  /// - Returns: Process basic info
  /// - Throws: DebuggerError on failure
  public func processInfo() throws -> ProcessBasicInfo {
    guard isValid else {
      throw DebuggerError.notAttached
    }

    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(
      MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)

    let kr = withUnsafeMutablePointer(to: &info) { infoPtr in
      infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { ptr in
        task_info(_port, task_flavor_t(MACH_TASK_BASIC_INFO), ptr, &count)
      }
    }

    guard kr == KERN_SUCCESS else {
      throw DebuggerError.threadOperationFailed(operation: "get process info")
    }

    return ProcessBasicInfo(
      virtualSize: vm_size_t(info.virtual_size),
      residentSize: vm_size_t(info.resident_size),
      suspendCount: info.suspend_count
    )
  }

  // MARK: - Suspend/Resume

  /// Suspend all threads in the target process
  /// - Throws: DebuggerError on failure
  public func suspend() throws {
    guard isValid else {
      throw DebuggerError.notAttached
    }

    let kr = task_suspend(_port)
    guard kr == KERN_SUCCESS else {
      throw DebuggerError.threadOperationFailed(operation: "suspend task")
    }
  }

  /// Resume all threads in the target process
  /// - Throws: DebuggerError on failure
  public func resume() throws {
    guard isValid else {
      throw DebuggerError.notAttached
    }

    let kr = task_resume(_port)
    guard kr == KERN_SUCCESS else {
      throw DebuggerError.threadOperationFailed(operation: "resume task")
    }
  }

  // MARK: - Error Mapping

  /// Map kernel return code to appropriate DebuggerError
  private static func mapKernelError(_ kr: kern_return_t, pid: pid_t) -> DebuggerError {
    switch kr {
    case KERN_FAILURE:
      // Check if process exists
      if kill(pid, 0) != 0 && errno == ESRCH {
        return .processNotFound(pid: pid)
      }
      return .attachFailed(pid: pid, reason: "task_for_pid failed (check entitlements)")

    case 5:  // KERN_INVALID_ARGUMENT
      return .invalidPID(pid: pid)

    default:
      // Check for permission issues
      if kr == KERN_FAILURE {
        return .permissionDenied(
          operation: "task_for_pid",
          guidance: "Ensure debugger entitlement is set and Developer Tools is enabled"
        )
      }
      return .attachFailed(pid: pid, reason: "task_for_pid returned \(kr)")
    }
  }
}

// MARK: - ProcessBasicInfo

/// Basic information about a process
public struct ProcessBasicInfo: Sendable {
  /// Virtual memory size in bytes
  public let virtualSize: vm_size_t

  /// Resident memory size in bytes
  public let residentSize: vm_size_t

  /// Current suspend count
  public let suspendCount: Int32
}

// MARK: - Debug Description

extension TaskPort: CustomDebugStringConvertible {
  public var debugDescription: String {
    "TaskPort(pid: \(pid), port: \(_port), valid: \(isValid))"
  }
}
