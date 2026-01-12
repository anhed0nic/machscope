// MemoryReader.swift
// DebuggerCore
//
// vm_read wrapper for reading process memory

import Darwin
import Foundation

/// Memory reader using Mach vm_read
///
/// Provides safe read access to a target process's memory through Mach APIs.
public struct MemoryReader: Sendable {

  /// Task port for the target process
  private let taskPort: mach_port_t

  // MARK: - Initialization

  /// Create a memory reader for a task port
  /// - Parameter taskPort: Mach task port with read access
  public init(taskPort: mach_port_t) {
    self.taskPort = taskPort
  }

  /// Create a memory reader from a TaskPort wrapper
  /// - Parameter task: TaskPort wrapper
  public init(task: TaskPort) {
    self.taskPort = task.port
  }

  // MARK: - Read Operations

  /// Read raw bytes from target memory
  /// - Parameters:
  ///   - address: Starting address to read from
  ///   - size: Number of bytes to read
  /// - Returns: Data containing the read bytes
  /// - Throws: DebuggerError if read fails
  public func read(at address: UInt64, size: Int) throws -> Data {
    guard size > 0 else {
      return Data()
    }

    var data: vm_offset_t = 0
    var dataCount: mach_msg_type_number_t = 0

    let kr = vm_read(
      taskPort,
      vm_address_t(address),
      vm_size_t(size),
      &data,
      &dataCount
    )

    guard kr == KERN_SUCCESS else {
      throw DebuggerError.memoryReadFailed(address: address, size: size)
    }

    defer {
      vm_deallocate(mach_task_self_, data, vm_size_t(dataCount))
    }

    return Data(bytes: UnsafeRawPointer(bitPattern: data)!, count: Int(dataCount))
  }

  /// Read a specific type from target memory
  /// - Parameters:
  ///   - type: Type to read
  ///   - address: Address to read from
  /// - Returns: Value of the specified type
  /// - Throws: DebuggerError if read fails
  public func read<T>(_ type: T.Type, at address: UInt64) throws -> T {
    let size = MemoryLayout<T>.size
    let data = try read(at: address, size: size)

    return data.withUnsafeBytes { buffer in
      buffer.load(as: T.self)
    }
  }

  /// Read a UInt8 from target memory
  /// - Parameter address: Address to read from
  /// - Returns: Byte value
  /// - Throws: DebuggerError if read fails
  public func readUInt8(at address: UInt64) throws -> UInt8 {
    try read(UInt8.self, at: address)
  }

  /// Read a UInt16 from target memory
  /// - Parameter address: Address to read from
  /// - Returns: UInt16 value
  /// - Throws: DebuggerError if read fails
  public func readUInt16(at address: UInt64) throws -> UInt16 {
    try read(UInt16.self, at: address)
  }

  /// Read a UInt32 from target memory (e.g., for instructions)
  /// - Parameter address: Address to read from
  /// - Returns: UInt32 value
  /// - Throws: DebuggerError if read fails
  public func readUInt32(at address: UInt64) throws -> UInt32 {
    try read(UInt32.self, at: address)
  }

  /// Read a UInt64 from target memory (e.g., for pointers)
  /// - Parameter address: Address to read from
  /// - Returns: UInt64 value
  /// - Throws: DebuggerError if read fails
  public func readUInt64(at address: UInt64) throws -> UInt64 {
    try read(UInt64.self, at: address)
  }

  /// Read a pointer from target memory
  /// - Parameter address: Address to read pointer from
  /// - Returns: Pointer value as UInt64
  /// - Throws: DebuggerError if read fails
  public func readPointer(at address: UInt64) throws -> UInt64 {
    try readUInt64(at: address)
  }

  /// Read a null-terminated C string from target memory
  /// - Parameters:
  ///   - address: Starting address of the string
  ///   - maxLength: Maximum number of bytes to read (default 1024)
  /// - Returns: The string, or nil if invalid
  /// - Throws: DebuggerError if read fails
  public func readCString(at address: UInt64, maxLength: Int = 1024) throws -> String? {
    let data = try read(at: address, size: maxLength)

    // Find null terminator
    guard let nullIndex = data.firstIndex(of: 0) else {
      // No null terminator found, use entire buffer
      return String(data: data, encoding: .utf8)
    }

    let stringData = data.prefix(upTo: nullIndex)
    return String(data: stringData, encoding: .utf8)
  }

  /// Read an ARM64 instruction from target memory
  /// - Parameter address: Address of the instruction (must be 4-byte aligned)
  /// - Returns: 32-bit instruction encoding
  /// - Throws: DebuggerError if read fails
  public func readInstruction(at address: UInt64) throws -> UInt32 {
    try readUInt32(at: address)
  }

  /// Read multiple instructions from target memory
  /// - Parameters:
  ///   - address: Starting address
  ///   - count: Number of instructions to read
  /// - Returns: Array of instruction encodings
  /// - Throws: DebuggerError if read fails
  public func readInstructions(at address: UInt64, count: Int) throws -> [UInt32] {
    let data = try read(at: address, size: count * 4)

    return data.withUnsafeBytes { buffer in
      let uint32Buffer = buffer.bindMemory(to: UInt32.self)
      return Array(uint32Buffer)
    }
  }

  // MARK: - Memory Region Info

  /// Get information about the memory region at an address
  /// - Parameter address: Address to query
  /// - Returns: Memory region info, or nil if not readable
  public func regionInfo(at address: UInt64) -> MemoryRegionInfo? {
    var regionAddress = vm_address_t(address)
    var regionSize: vm_size_t = 0
    var info = vm_region_basic_info_data_64_t()
    // VM_REGION_BASIC_INFO_COUNT_64 = sizeof(vm_region_basic_info_data_64_t) / sizeof(int)
    var infoCount = mach_msg_type_number_t(
      MemoryLayout<vm_region_basic_info_data_64_t>.size / MemoryLayout<Int32>.size)
    var objectName: mach_port_t = 0

    let kr = withUnsafeMutablePointer(to: &info) { infoPtr in
      infoPtr.withMemoryRebound(to: Int32.self, capacity: Int(infoCount)) { ptr in
        vm_region_64(
          taskPort,
          &regionAddress,
          &regionSize,
          VM_REGION_BASIC_INFO_64,
          ptr,
          &infoCount,
          &objectName
        )
      }
    }

    guard kr == KERN_SUCCESS else {
      return nil
    }

    return MemoryRegionInfo(
      address: UInt64(regionAddress),
      size: UInt64(regionSize),
      protection: VMProtection(rawValue: UInt32(info.protection)),
      maxProtection: VMProtection(rawValue: UInt32(info.max_protection)),
      shared: info.shared != 0
    )
  }

  /// Check if an address is readable
  /// - Parameter address: Address to check
  /// - Returns: true if the address can be read
  public func isReadable(at address: UInt64) -> Bool {
    guard let info = regionInfo(at: address) else {
      return false
    }
    return info.protection.contains(.read)
  }
}

// MARK: - Memory Region Info

/// Information about a memory region
public struct MemoryRegionInfo: Sendable {
  /// Base address of the region
  public let address: UInt64

  /// Size of the region in bytes
  public let size: UInt64

  /// Current protection flags
  public let protection: VMProtection

  /// Maximum protection flags
  public let maxProtection: VMProtection

  /// Whether the region is shared
  public let shared: Bool

  /// End address (exclusive)
  public var endAddress: UInt64 {
    address + size
  }

  /// Check if an address is within this region
  public func contains(_ addr: UInt64) -> Bool {
    addr >= address && addr < endAddress
  }
}

// MARK: - VM Protection

/// Virtual memory protection flags
public struct VMProtection: OptionSet, Sendable {
  public let rawValue: UInt32

  public init(rawValue: UInt32) {
    self.rawValue = rawValue
  }

  /// Read access
  public static let read = VMProtection(rawValue: 1)

  /// Write access
  public static let write = VMProtection(rawValue: 2)

  /// Execute access
  public static let execute = VMProtection(rawValue: 4)

  /// Read and execute (typical for code)
  public static let rx: VMProtection = [.read, .execute]

  /// Read and write (typical for data)
  public static let rw: VMProtection = [.read, .write]

  /// All permissions
  public static let all: VMProtection = [.read, .write, .execute]
}

extension VMProtection: CustomStringConvertible {
  public var description: String {
    var result = ""
    result += contains(.read) ? "r" : "-"
    result += contains(.write) ? "w" : "-"
    result += contains(.execute) ? "x" : "-"
    return result
  }
}
