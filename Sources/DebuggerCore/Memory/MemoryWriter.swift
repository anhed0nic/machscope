// MemoryWriter.swift
// DebuggerCore
//
// vm_write wrapper for writing process memory

import Darwin
import Foundation

/// Memory writer using Mach vm_write
///
/// Provides safe write access to a target process's memory through Mach APIs.
/// Note: Writing to memory requires appropriate permissions and may need
/// the target memory to be writable.
public struct MemoryWriter: Sendable {

  /// Task port for the target process
  private let taskPort: mach_port_t

  // MARK: - Initialization

  /// Create a memory writer for a task port
  /// - Parameter taskPort: Mach task port with write access
  public init(taskPort: mach_port_t) {
    self.taskPort = taskPort
  }

  /// Create a memory writer from a TaskPort wrapper
  /// - Parameter task: TaskPort wrapper
  public init(task: TaskPort) {
    self.taskPort = task.port
  }

  // MARK: - Write Operations

  /// Write raw bytes to target memory
  /// - Parameters:
  ///   - data: Data to write
  ///   - address: Address to write to
  /// - Throws: DebuggerError if write fails
  public func write(_ data: Data, at address: UInt64) throws {
    guard !data.isEmpty else {
      return
    }

    let kr = data.withUnsafeBytes { buffer in
      vm_write(
        taskPort,
        vm_address_t(address),
        vm_offset_t(bitPattern: buffer.baseAddress),
        mach_msg_type_number_t(data.count)
      )
    }

    guard kr == KERN_SUCCESS else {
      throw DebuggerError.memoryWriteFailed(address: address, size: data.count)
    }
  }

  /// Write a specific type to target memory
  /// - Parameters:
  ///   - value: Value to write
  ///   - address: Address to write to
  /// - Throws: DebuggerError if write fails
  public func write<T>(_ value: T, at address: UInt64) throws {
    var mutableValue = value
    let size = MemoryLayout<T>.size

    let kr = withUnsafeBytes(of: &mutableValue) { buffer in
      vm_write(
        taskPort,
        vm_address_t(address),
        vm_offset_t(bitPattern: buffer.baseAddress),
        mach_msg_type_number_t(size)
      )
    }

    guard kr == KERN_SUCCESS else {
      throw DebuggerError.memoryWriteFailed(address: address, size: size)
    }
  }

  /// Write a UInt8 to target memory
  /// - Parameters:
  ///   - value: Byte value to write
  ///   - address: Address to write to
  /// - Throws: DebuggerError if write fails
  public func writeUInt8(_ value: UInt8, at address: UInt64) throws {
    try write(value, at: address)
  }

  /// Write a UInt16 to target memory
  /// - Parameters:
  ///   - value: Value to write
  ///   - address: Address to write to
  /// - Throws: DebuggerError if write fails
  public func writeUInt16(_ value: UInt16, at address: UInt64) throws {
    try write(value, at: address)
  }

  /// Write a UInt32 to target memory (e.g., for instructions)
  /// - Parameters:
  ///   - value: Value to write
  ///   - address: Address to write to
  /// - Throws: DebuggerError if write fails
  public func writeUInt32(_ value: UInt32, at address: UInt64) throws {
    try write(value, at: address)
  }

  /// Write a UInt64 to target memory (e.g., for pointers)
  /// - Parameters:
  ///   - value: Value to write
  ///   - address: Address to write to
  /// - Throws: DebuggerError if write fails
  public func writeUInt64(_ value: UInt64, at address: UInt64) throws {
    try write(value, at: address)
  }

  /// Write an ARM64 instruction to target memory
  /// - Parameters:
  ///   - instruction: 32-bit instruction encoding
  ///   - address: Address to write to (must be 4-byte aligned)
  /// - Throws: DebuggerError if write fails
  public func writeInstruction(_ instruction: UInt32, at address: UInt64) throws {
    try writeUInt32(instruction, at: address)
  }

  // MARK: - Memory Protection

  /// Change memory protection for a region
  /// - Parameters:
  ///   - address: Starting address
  ///   - size: Size of the region
  ///   - protection: New protection flags
  /// - Returns: Original protection flags
  /// - Throws: DebuggerError if protection change fails
  @discardableResult
  public func protect(
    at address: UInt64,
    size: Int,
    protection: VMProtection
  ) throws -> VMProtection {
    // Get original protection first
    let reader = MemoryReader(taskPort: taskPort)
    guard let info = reader.regionInfo(at: address) else {
      throw DebuggerError.memoryWriteFailed(address: address, size: size)
    }

    let originalProtection = info.protection

    let kr = vm_protect(
      taskPort,
      vm_address_t(address),
      vm_size_t(size),
      0,  // Set current, not max protection
      vm_prot_t(protection.rawValue)
    )

    guard kr == KERN_SUCCESS else {
      throw DebuggerError.memoryWriteFailed(address: address, size: size)
    }

    return originalProtection
  }

  /// Write to memory with temporary protection change
  /// - Parameters:
  ///   - data: Data to write
  ///   - address: Address to write to
  /// - Throws: DebuggerError if write fails
  ///
  /// This method temporarily makes the memory writable, writes the data,
  /// then restores the original protection. Useful for writing to code segments.
  public func writeWithProtectionChange(_ data: Data, at address: UInt64) throws {
    let size = data.count

    // Save original protection and make writable
    let original = try protect(at: address, size: size, protection: .rw)

    defer {
      // Restore original protection
      try? protect(at: address, size: size, protection: original)
    }

    try write(data, at: address)
  }

  /// Write an instruction with temporary protection change
  /// - Parameters:
  ///   - instruction: 32-bit instruction encoding
  ///   - address: Address to write to
  /// - Throws: DebuggerError if write fails
  ///
  /// This is useful for setting software breakpoints in code.
  public func writeInstructionWithProtectionChange(_ instruction: UInt32, at address: UInt64) throws
  {
    var mutableInstruction = instruction
    let data = Data(bytes: &mutableInstruction, count: 4)
    try writeWithProtectionChange(data, at: address)
  }
}
