// MemoryMappedFile.swift
// MachOKit
//
// Memory-mapped file wrapper using mmap for efficient large binary access

import Darwin
import Foundation

/// Threshold for using memory-mapped I/O (10 MB)
public let memoryMapThreshold: Int = 10 * 1024 * 1024

/// Memory-mapped file for efficient large binary access
///
/// Uses mmap() to map the file into virtual memory, providing:
/// - Efficient random access without loading entire file into RAM
/// - Automatic page-in/page-out by the kernel
/// - Shared memory with other processes reading the same file
///
/// Thread Safety: This class is `@unchecked Sendable` because the underlying
/// mapped memory is read-only and the file descriptor is not modified after init.
public final class MemoryMappedFile: @unchecked Sendable {
  /// Pointer to the mapped memory region
  private let pointer: UnsafeRawPointer

  /// Size of the mapped file in bytes
  public let size: Int

  /// File descriptor (kept open while mapped)
  private let fileDescriptor: Int32

  /// Path to the mapped file
  public let path: String

  /// Create a memory-mapped file
  /// - Parameter path: Path to the file to map
  /// - Throws: MachOParseError if the file cannot be opened or mapped
  public init(path: String) throws {
    self.path = path

    // Open file in read-only mode
    fileDescriptor = open(path, O_RDONLY)
    guard fileDescriptor >= 0 else {
      if errno == ENOENT {
        throw MachOParseError.fileNotFound(path: path)
      }
      throw MachOParseError.fileAccessError(
        path: path,
        underlying: POSIXError(errno: errno)
      )
    }

    // Get file size
    var statInfo = stat()
    guard fstat(fileDescriptor, &statInfo) == 0 else {
      close(fileDescriptor)
      throw MachOParseError.fileAccessError(
        path: path,
        underlying: POSIXError(errno: errno)
      )
    }

    size = Int(statInfo.st_size)

    // Handle empty files
    guard size > 0 else {
      close(fileDescriptor)
      throw MachOParseError.insufficientData(offset: 0, needed: 1, available: 0)
    }

    // Map the file into memory
    let mapped = mmap(
      nil,  // Let kernel choose address
      size,  // Map entire file
      PROT_READ,  // Read-only access
      MAP_PRIVATE,  // Private mapping (COW if written)
      fileDescriptor,  // File descriptor
      0  // Start from beginning
    )

    guard mapped != MAP_FAILED else {
      close(fileDescriptor)
      throw MachOParseError.fileAccessError(
        path: path,
        underlying: POSIXError(errno: errno)
      )
    }

    pointer = UnsafeRawPointer(mapped!)
  }

  deinit {
    // Unmap the memory region
    munmap(UnsafeMutableRawPointer(mutating: pointer), size)
    // Close the file descriptor
    close(fileDescriptor)
  }

  /// Access the raw pointer to the mapped memory
  /// - Warning: The pointer is only valid for the lifetime of this object
  public var rawPointer: UnsafeRawPointer {
    pointer
  }

  /// Read a value of the specified type at the given offset
  /// - Parameters:
  ///   - type: The type to read
  ///   - offset: Byte offset into the file
  /// - Returns: The value read
  /// - Throws: MachOParseError.insufficientData if out of bounds
  public func read<T>(_ type: T.Type, at offset: Int) throws -> T {
    let typeSize = MemoryLayout<T>.size
    guard offset >= 0 && offset + typeSize <= size else {
      throw MachOParseError.insufficientData(
        offset: offset,
        needed: typeSize,
        available: max(0, size - offset)
      )
    }
    return pointer.advanced(by: offset).load(as: T.self)
  }

  /// Read bytes at the specified offset
  /// - Parameters:
  ///   - offset: Byte offset into the file
  ///   - count: Number of bytes to read
  /// - Returns: The bytes as Data
  /// - Throws: MachOParseError.insufficientData if out of bounds
  public func readBytes(at offset: Int, count: Int) throws -> Data {
    guard offset >= 0 && count >= 0 && offset + count <= size else {
      throw MachOParseError.insufficientData(
        offset: offset,
        needed: count,
        available: max(0, size - offset)
      )
    }
    return Data(bytes: pointer.advanced(by: offset), count: count)
  }

  /// Create a BinaryReader for a slice of the mapped file
  /// - Parameters:
  ///   - offset: Starting offset
  ///   - count: Number of bytes in the slice
  /// - Returns: A BinaryReader for the specified range
  /// - Throws: MachOParseError.insufficientData if out of bounds
  public func slice(at offset: Int, count: Int) throws -> BinaryReader {
    let data = try readBytes(at: offset, count: count)
    return BinaryReader(data: data)
  }

  /// Create a BinaryReader for the entire mapped file
  /// - Returns: A BinaryReader for the entire file
  public func reader() -> BinaryReader {
    let data = Data(bytes: pointer, count: size)
    return BinaryReader(data: data)
  }
}

// MARK: - BinaryProviding Conformance

extension MemoryMappedFile: BinaryProviding {}

// MARK: - POSIX Error Helper

/// Wrapper for POSIX errno values
private struct POSIXError: Error, CustomStringConvertible {
  let errno: Int32

  init(errno: Int32) {
    self.errno = errno
  }

  var description: String {
    String(cString: strerror(errno))
  }
}

// MARK: - Factory Functions

/// Load a binary file, using memory mapping for large files
/// - Parameters:
///   - path: Path to the file
///   - forceMemoryMap: If true, always use memory mapping regardless of size
/// - Returns: A BinaryReader for the file contents
/// - Throws: MachOParseError if the file cannot be read
public func loadBinary(at path: String, forceMemoryMap: Bool = false) throws -> BinaryReader {
  // Get file size
  let fileManager = FileManager.default
  guard fileManager.fileExists(atPath: path) else {
    throw MachOParseError.fileNotFound(path: path)
  }

  let attributes = try fileManager.attributesOfItem(atPath: path)
  let fileSize = attributes[.size] as? Int ?? 0

  // Use memory mapping for large files
  if forceMemoryMap || fileSize > memoryMapThreshold {
    let mapped = try MemoryMappedFile(path: path)
    return mapped.reader()
  }

  // Load small files directly into memory
  let url = URL(fileURLWithPath: path)
  do {
    let data = try Data(contentsOf: url)
    return BinaryReader(data: data)
  } catch {
    throw MachOParseError.fileAccessError(path: path, underlying: error)
  }
}
