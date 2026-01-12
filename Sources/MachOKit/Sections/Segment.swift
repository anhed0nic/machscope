// Segment.swift
// MachOKit
//
// Memory segment structure
//
// Note: VMProtection is defined in SegmentCommand.swift
// This file provides the Segment convenience wrapper

import Foundation

/// Memory segment from LC_SEGMENT_64
///
/// This is a convenience wrapper around SegmentCommand that provides
/// a cleaner interface for common operations.
public struct Segment: Sendable {
  /// Segment name
  public let name: String

  /// Virtual memory address
  public let vmAddress: UInt64

  /// Virtual memory size
  public let vmSize: UInt64

  /// File offset
  public let fileOffset: UInt64

  /// File size
  public let fileSize: UInt64

  /// Maximum VM protection
  public let maxProtection: VMProtection

  /// Initial VM protection
  public let initialProtection: VMProtection

  /// Segment flags
  public let flags: UInt32

  /// Sections within this segment
  public let sections: [Section]

  /// Create a Segment from a SegmentCommand
  public init(from command: SegmentCommand) {
    self.name = command.name
    self.vmAddress = command.vmAddress
    self.vmSize = command.vmSize
    self.fileOffset = command.fileOffset
    self.fileSize = command.fileSize
    self.maxProtection = command.maxProtection
    self.initialProtection = command.initialProtection
    self.flags = command.flags
    self.sections = command.sections
  }

  /// Check if this segment contains the given virtual address
  public func contains(address: UInt64) -> Bool {
    address >= vmAddress && address < vmAddress + vmSize
  }

  /// Find a section by name
  public func section(named name: String) -> Section? {
    sections.first { $0.name == name }
  }

  /// Check if this segment is readable
  public var isReadable: Bool {
    initialProtection.contains(.read)
  }

  /// Check if this segment is writable
  public var isWritable: Bool {
    initialProtection.contains(.write)
  }

  /// Check if this segment is executable
  public var isExecutable: Bool {
    initialProtection.contains(.execute)
  }
}
