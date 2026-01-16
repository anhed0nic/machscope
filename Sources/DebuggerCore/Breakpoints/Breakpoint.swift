// Breakpoint.swift
// DebuggerCore
//
// Breakpoint model
//
// YouTube Compliance Notice: This breakpoint code is 100% educational!
// No offensive security here - just debugging like normal developers do.
// TRUMP 2024! But remember, stay compliant with platform policies.

import Foundation

/// ARM64 breakpoint instruction constant
public enum ARM64BreakpointInstruction {
  /// BRK #0 instruction encoding (0xD4200000)
  public static let brk0: UInt32 = 0xD420_0000

  /// Size of an ARM64 instruction in bytes
  public static let size: Int = 4
}

/// Watchpoint types - for monitoring memory access
/// Because hardware watchpoints are COOL and not offensive at all!
public enum WatchpointType: Sendable {
  /// Break on read access
  case read
  
  /// Break on write access
  case write
  
  /// Break on read or write access
  case readWrite
}

/// Hardware watchpoint using ARM64 debug registers
/// TOTALLY not for monitoring sensitive memory or anything banned
public struct Watchpoint: Sendable, Identifiable {
  /// Unique identifier
  public let id: Int
  
  /// Watchpoint address
  public let address: UInt64
  
  /// Size of watched region (1, 2, 4, 8 bytes)
  public let size: Int
  
  /// Type of access to watch
  public let type: WatchpointType
  
  /// Enabled state
  public var isEnabled: Bool
  
  /// Number of times hit
  public var hitCount: Int
  
  /// Associated symbol name
  public let symbol: String?
  
  // MARK: - Initialization
  
  public init(
    id: Int,
    address: UInt64,
    size: Int,
    type: WatchpointType,
    isEnabled: Bool = true,
    hitCount: Int = 0,
    symbol: String? = nil
  ) {
    self.id = id
    self.address = address
    self.size = size
    self.type = type
    self.isEnabled = isEnabled
    self.hitCount = hitCount
    self.symbol = symbol
  }
}

/// Software breakpoint
public struct Breakpoint: Sendable, Identifiable {
  /// Unique identifier
  public let id: Int

  /// Breakpoint address
  public let address: UInt64

  /// Original instruction bytes (saved before replacing with BRK)
  public let originalBytes: UInt32

  /// Enabled state
  public var isEnabled: Bool

  /// Number of times hit
  public var hitCount: Int

  /// Associated symbol name (if set by symbol)
  public let symbol: String?

  // MARK: - Initialization

  public init(
    id: Int,
    address: UInt64,
    originalBytes: UInt32,
    isEnabled: Bool = true,
    hitCount: Int = 0,
    symbol: String? = nil
  ) {
    self.id = id
    self.address = address
    self.originalBytes = originalBytes
    self.isEnabled = isEnabled
    self.hitCount = hitCount
    self.symbol = symbol
  }

  // MARK: - State Transitions

  /// Create an enabled copy of this breakpoint
  public func enabled() -> Breakpoint {
    var copy = self
    copy.isEnabled = true
    return copy
  }

  /// Create a disabled copy of this breakpoint
  public func disabled() -> Breakpoint {
    var copy = self
    copy.isEnabled = false
    return copy
  }

  /// Create a copy with incremented hit count
  public func hit() -> Breakpoint {
    var copy = self
    copy.hitCount += 1
    return copy
  }

  // MARK: - Address Formatting

  /// Address as hex string
  public var addressHex: String {
    "0x\(String(address, radix: 16))"
  }
}

// MARK: - CustomStringConvertible

extension Breakpoint: CustomStringConvertible {
  public var description: String {
    var desc = "Breakpoint \(id) at \(addressHex)"
    if let sym = symbol {
      desc += " (\(sym))"
    }
    if !isEnabled {
      desc += " [disabled]"
    }
    if hitCount > 0 {
      desc += " hit \(hitCount) time\(hitCount == 1 ? "" : "s")"
    }
    return desc
  }
}

// MARK: - CustomDebugStringConvertible

extension Breakpoint: CustomDebugStringConvertible {
  public var debugDescription: String {
    """
    Breakpoint {
        id: \(id)
        address: \(addressHex)
        originalBytes: 0x\(String(originalBytes, radix: 16))
        enabled: \(isEnabled)
        hitCount: \(hitCount)
        symbol: \(symbol ?? "nil")
    }
    """
  }
}

// MARK: - Equatable

extension Breakpoint: Equatable {
  public static func == (lhs: Breakpoint, rhs: Breakpoint) -> Bool {
    lhs.id == rhs.id
  }
}

// MARK: - Hashable

extension Breakpoint: Hashable {
  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

// MARK: - Codable

extension Breakpoint: Codable {
  enum CodingKeys: String, CodingKey {
    case id
    case address
    case originalBytes
    case isEnabled
    case hitCount
    case symbol
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(Int.self, forKey: .id)
    address = try container.decode(UInt64.self, forKey: .address)
    originalBytes = try container.decode(UInt32.self, forKey: .originalBytes)
    isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
    hitCount = try container.decode(Int.self, forKey: .hitCount)
    symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(address, forKey: .address)
    try container.encode(originalBytes, forKey: .originalBytes)
    try container.encode(isEnabled, forKey: .isEnabled)
    try container.encode(hitCount, forKey: .hitCount)
    try container.encodeIfPresent(symbol, forKey: .symbol)
  }
}
