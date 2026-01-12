// BreakpointManager.swift
// DebuggerCore
//
// Breakpoint set/remove/hit management

import Foundation

/// Breakpoint manager for tracking and managing software breakpoints
///
/// This class manages the lifecycle of breakpoints including:
/// - Adding and removing breakpoints
/// - Enabling and disabling breakpoints
/// - Tracking hit counts
/// - Looking up breakpoints by ID or address
public final class BreakpointManager: @unchecked Sendable {

  /// Storage for breakpoints
  private var _breakpoints: [Int: Breakpoint] = [:]

  /// Lock for thread-safe access
  private let lock = NSLock()

  /// Next breakpoint ID to assign
  private var nextID: Int = 1

  // MARK: - Initialization

  public init() {}

  // MARK: - Breakpoint Access

  /// All breakpoints
  public var breakpoints: [Breakpoint] {
    lock.lock()
    defer { lock.unlock() }
    return Array(_breakpoints.values).sorted { $0.id < $1.id }
  }

  /// Number of breakpoints
  public var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return _breakpoints.count
  }

  /// Enabled breakpoints only
  public var enabledBreakpoints: [Breakpoint] {
    lock.lock()
    defer { lock.unlock() }
    return _breakpoints.values.filter { $0.isEnabled }.sorted { $0.id < $1.id }
  }

  /// Get breakpoint by ID
  /// - Parameter id: Breakpoint ID
  /// - Returns: Breakpoint if found
  public func breakpoint(id: Int) -> Breakpoint? {
    lock.lock()
    defer { lock.unlock() }
    return _breakpoints[id]
  }

  /// Get breakpoint by address
  /// - Parameter address: Address to look up
  /// - Returns: Breakpoint if found at that address
  public func breakpoint(at address: UInt64) -> Breakpoint? {
    lock.lock()
    defer { lock.unlock() }
    return _breakpoints.values.first { $0.address == address }
  }

  // MARK: - Breakpoint Management

  /// Add a new breakpoint
  /// - Parameters:
  ///   - address: Address for the breakpoint
  ///   - symbol: Optional symbol name
  ///   - originalBytes: Original instruction bytes (0 if not yet read)
  /// - Returns: The assigned breakpoint ID
  /// - Throws: DebuggerError if breakpoint cannot be added
  @discardableResult
  public func addBreakpoint(
    at address: UInt64,
    symbol: String? = nil,
    originalBytes: UInt32 = 0
  ) throws -> Int {
    lock.lock()
    defer { lock.unlock() }

    // Check for duplicate address
    if _breakpoints.values.contains(where: { $0.address == address }) {
      // Breakpoint already exists at this address, return existing ID
      if let existing = _breakpoints.values.first(where: { $0.address == address }) {
        return existing.id
      }
    }

    let id = nextID
    nextID += 1

    let bp = Breakpoint(
      id: id,
      address: address,
      originalBytes: originalBytes,
      isEnabled: true,
      hitCount: 0,
      symbol: symbol
    )

    _breakpoints[id] = bp
    return id
  }

  /// Remove a breakpoint
  /// - Parameter id: Breakpoint ID to remove
  /// - Throws: DebuggerError if breakpoint not found
  public func removeBreakpoint(id: Int) throws {
    lock.lock()
    defer { lock.unlock() }

    guard _breakpoints.removeValue(forKey: id) != nil else {
      throw DebuggerError.breakpointNotFound(id: id)
    }
  }

  /// Remove breakpoint at an address
  /// - Parameter address: Address to remove breakpoint from
  /// - Returns: The removed breakpoint, if any
  @discardableResult
  public func removeBreakpoint(at address: UInt64) -> Breakpoint? {
    lock.lock()
    defer { lock.unlock() }

    guard let bp = _breakpoints.values.first(where: { $0.address == address }) else {
      return nil
    }

    return _breakpoints.removeValue(forKey: bp.id)
  }

  /// Enable a breakpoint
  /// - Parameter id: Breakpoint ID
  /// - Throws: DebuggerError if breakpoint not found
  public func enableBreakpoint(id: Int) throws {
    lock.lock()
    defer { lock.unlock() }

    guard var bp = _breakpoints[id] else {
      throw DebuggerError.breakpointNotFound(id: id)
    }

    bp.isEnabled = true
    _breakpoints[id] = bp
  }

  /// Disable a breakpoint
  /// - Parameter id: Breakpoint ID
  /// - Throws: DebuggerError if breakpoint not found
  public func disableBreakpoint(id: Int) throws {
    lock.lock()
    defer { lock.unlock() }

    guard var bp = _breakpoints[id] else {
      throw DebuggerError.breakpointNotFound(id: id)
    }

    bp.isEnabled = false
    _breakpoints[id] = bp
  }

  /// Record a breakpoint hit
  /// - Parameter id: Breakpoint ID that was hit
  public func recordHit(id: Int) {
    lock.lock()
    defer { lock.unlock() }

    guard var bp = _breakpoints[id] else {
      return
    }

    bp.hitCount += 1
    _breakpoints[id] = bp
  }

  /// Record a breakpoint hit by address
  /// - Parameter address: Address that was hit
  /// - Returns: The breakpoint that was hit, if any
  @discardableResult
  public func recordHit(at address: UInt64) -> Breakpoint? {
    lock.lock()
    defer { lock.unlock() }

    guard var bp = _breakpoints.values.first(where: { $0.address == address }) else {
      return nil
    }

    bp.hitCount += 1
    _breakpoints[bp.id] = bp
    return bp
  }

  /// Update original bytes for a breakpoint
  /// - Parameters:
  ///   - id: Breakpoint ID
  ///   - originalBytes: Original instruction bytes
  public func updateOriginalBytes(id: Int, originalBytes: UInt32) {
    lock.lock()
    defer { lock.unlock() }

    guard let bp = _breakpoints[id] else {
      return
    }

    // Create a new breakpoint with updated original bytes
    let updated = Breakpoint(
      id: bp.id,
      address: bp.address,
      originalBytes: originalBytes,
      isEnabled: bp.isEnabled,
      hitCount: bp.hitCount,
      symbol: bp.symbol
    )

    _breakpoints[id] = updated
  }

  /// Clear all breakpoints
  public func clearAll() {
    lock.lock()
    defer { lock.unlock() }
    _breakpoints.removeAll()
  }

  /// Check if there's a breakpoint at an address
  /// - Parameter address: Address to check
  /// - Returns: true if breakpoint exists at address
  public func hasBreakpoint(at address: UInt64) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return _breakpoints.values.contains { $0.address == address }
  }

  /// Check if there's an enabled breakpoint at an address
  /// - Parameter address: Address to check
  /// - Returns: true if enabled breakpoint exists at address
  public func hasEnabledBreakpoint(at address: UInt64) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return _breakpoints.values.contains { $0.address == address && $0.isEnabled }
  }
}

// MARK: - Debug Description

extension BreakpointManager: CustomDebugStringConvertible {
  public var debugDescription: String {
    "BreakpointManager(count: \(count))"
  }
}
