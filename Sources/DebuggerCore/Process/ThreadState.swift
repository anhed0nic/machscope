// ThreadState.swift
// DebuggerCore
//
// Thread management

import Darwin
import Foundation

/// Thread state representing a single thread in the target process
public struct ThreadState: Sendable {

  /// Mach thread port
  public let threadID: thread_t

  /// ARM64 register state
  public var registers: ARM64Registers

  /// Whether the thread is suspended
  public var isSuspended: Bool

  // MARK: - Initialization

  public init(threadID: thread_t, registers: ARM64Registers, isSuspended: Bool) {
    self.threadID = threadID
    self.registers = registers
    self.isSuspended = isSuspended
  }

  /// Create ThreadState by reading from a live thread
  /// - Parameter thread: Thread port to read from
  /// - Returns: ThreadState with current register values
  /// - Throws: DebuggerError if reading fails
  #if arch(arm64)
    public static func read(from thread: thread_t) throws -> ThreadState {
      var state = arm_thread_state64_t()
      // ARM_THREAD_STATE64_COUNT = sizeof(arm_thread_state64_t)/sizeof(uint32_t)
      let ARM_THREAD_STATE64_COUNT_LOCAL = mach_msg_type_number_t(
        MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<UInt32>.size
      )
      var count = ARM_THREAD_STATE64_COUNT_LOCAL

      let kr = withUnsafeMutablePointer(to: &state) { statePtr in
        statePtr.withMemoryRebound(to: UInt32.self, capacity: Int(count)) { ptr in
          thread_get_state(thread, ARM_THREAD_STATE64, ptr, &count)
        }
      }

      guard kr == KERN_SUCCESS else {
        throw DebuggerError.threadOperationFailed(operation: "get thread state")
      }

      let registers = ARM64Registers.from(threadState: state)

      // Check if thread is suspended
      var info = thread_basic_info()
      // THREAD_BASIC_INFO_COUNT = sizeof(thread_basic_info_data_t)/sizeof(natural_t)
      let THREAD_BASIC_INFO_COUNT_LOCAL = mach_msg_type_number_t(
        MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<natural_t>.size
      )
      var infoCount = THREAD_BASIC_INFO_COUNT_LOCAL

      let infoKr = withUnsafeMutablePointer(to: &info) { infoPtr in
        infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) { ptr in
          thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), ptr, &infoCount)
        }
      }

      let suspended = infoKr == KERN_SUCCESS && info.suspend_count > 0

      return ThreadState(
        threadID: thread,
        registers: registers,
        isSuspended: suspended
      )
    }
  #endif

  // MARK: - Register Access

  /// Program counter
  public var pc: UInt64 {
    registers.pc
  }

  /// Stack pointer
  public var sp: UInt64 {
    registers.sp
  }

  /// Frame pointer (x29)
  public var fp: UInt64 {
    registers.x29
  }

  /// Link register (x30)
  public var lr: UInt64 {
    registers.x30
  }

  // MARK: - Thread Operations

  /// Suspend this thread
  /// - Throws: DebuggerError on failure
  public mutating func suspend() throws {
    let kr = thread_suspend(threadID)
    guard kr == KERN_SUCCESS else {
      throw DebuggerError.threadOperationFailed(operation: "suspend thread")
    }
    isSuspended = true
  }

  /// Resume this thread
  /// - Throws: DebuggerError on failure
  public mutating func resume() throws {
    let kr = thread_resume(threadID)
    guard kr == KERN_SUCCESS else {
      throw DebuggerError.threadOperationFailed(operation: "resume thread")
    }
    isSuspended = false
  }

  /// Write registers back to the thread
  /// - Throws: DebuggerError on failure
  #if arch(arm64)
    public func writeRegisters() throws {
      var state = registers.toThreadState()
      let count = mach_msg_type_number_t(
        MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<UInt32>.size
      )

      let kr = withUnsafeMutablePointer(to: &state) { statePtr in
        statePtr.withMemoryRebound(to: UInt32.self, capacity: Int(count)) { ptr in
          thread_set_state(threadID, ARM_THREAD_STATE64, ptr, count)
        }
      }

      guard kr == KERN_SUCCESS else {
        throw DebuggerError.threadOperationFailed(operation: "set thread state")
      }
    }
  #endif

  /// Single step this thread (execute one instruction)
  /// - Throws: DebuggerError on failure
  #if arch(arm64)
    public mutating func singleStep() throws {
      // On ARM64, single stepping is done via debug registers
      // This is a simplified implementation that modifies MDSCR_EL1 equivalent

      var state = arm_debug_state64_t()
      // ARM_DEBUG_STATE64_COUNT = sizeof(arm_debug_state64_t)/sizeof(uint32_t)
      var count = mach_msg_type_number_t(
        MemoryLayout<arm_debug_state64_t>.size / MemoryLayout<UInt32>.size
      )

      // Get current debug state
      var kr = withUnsafeMutablePointer(to: &state) { statePtr in
        statePtr.withMemoryRebound(to: UInt32.self, capacity: Int(count)) { ptr in
          thread_get_state(threadID, ARM_DEBUG_STATE64, ptr, &count)
        }
      }

      guard kr == KERN_SUCCESS else {
        throw DebuggerError.threadOperationFailed(operation: "get debug state")
      }

      // Enable software single step
      // Note: The actual implementation depends on macOS version
      state.__mdscr_el1 |= 1  // SS bit

      kr = withUnsafeMutablePointer(to: &state) { statePtr in
        statePtr.withMemoryRebound(to: UInt32.self, capacity: Int(count)) { ptr in
          thread_set_state(threadID, ARM_DEBUG_STATE64, ptr, count)
        }
      }

      guard kr == KERN_SUCCESS else {
        throw DebuggerError.threadOperationFailed(operation: "set debug state")
      }
    }
  #endif
}

// MARK: - CustomStringConvertible

extension ThreadState: CustomStringConvertible {
  public var description: String {
    let status = isSuspended ? "suspended" : "running"
    return "Thread \(threadID) (\(status)) at 0x\(String(pc, radix: 16))"
  }
}

// MARK: - CustomDebugStringConvertible

extension ThreadState: CustomDebugStringConvertible {
  public var debugDescription: String {
    """
    ThreadState {
        threadID: \(threadID)
        suspended: \(isSuspended)
        pc: 0x\(String(pc, radix: 16))
        sp: 0x\(String(sp, radix: 16))
        lr: 0x\(String(lr, radix: 16))
    }
    """
  }
}
