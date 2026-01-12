// ARM64Registers.swift
// DebuggerCore
//
// ARM64 register state for debugging

import Darwin
import Foundation

/// ARM64 register state for debugging
public struct ARM64Registers: Sendable, Codable, Equatable {
  // General purpose registers x0-x28
  public var x0: UInt64 = 0
  public var x1: UInt64 = 0
  public var x2: UInt64 = 0
  public var x3: UInt64 = 0
  public var x4: UInt64 = 0
  public var x5: UInt64 = 0
  public var x6: UInt64 = 0
  public var x7: UInt64 = 0
  public var x8: UInt64 = 0
  public var x9: UInt64 = 0
  public var x10: UInt64 = 0
  public var x11: UInt64 = 0
  public var x12: UInt64 = 0
  public var x13: UInt64 = 0
  public var x14: UInt64 = 0
  public var x15: UInt64 = 0
  public var x16: UInt64 = 0
  public var x17: UInt64 = 0
  public var x18: UInt64 = 0
  public var x19: UInt64 = 0
  public var x20: UInt64 = 0
  public var x21: UInt64 = 0
  public var x22: UInt64 = 0
  public var x23: UInt64 = 0
  public var x24: UInt64 = 0
  public var x25: UInt64 = 0
  public var x26: UInt64 = 0
  public var x27: UInt64 = 0
  public var x28: UInt64 = 0

  /// Frame pointer (x29)
  public var x29: UInt64 = 0

  /// Link register (x30)
  public var x30: UInt64 = 0

  /// Stack pointer
  public var sp: UInt64 = 0

  /// Program counter
  public var pc: UInt64 = 0

  /// Current program status register
  public var cpsr: UInt32 = 0

  public init() {}

  // MARK: - Register Aliases

  /// Frame pointer alias for x29
  public var fp: UInt64 {
    get { x29 }
    set { x29 = newValue }
  }

  /// Link register alias for x30
  public var lr: UInt64 {
    get { x30 }
    set { x30 = newValue }
  }

  // MARK: - Subscript Access

  /// Access general purpose registers by index (0-28)
  public subscript(index: Int) -> UInt64 {
    get {
      switch index {
      case 0: return x0
      case 1: return x1
      case 2: return x2
      case 3: return x3
      case 4: return x4
      case 5: return x5
      case 6: return x6
      case 7: return x7
      case 8: return x8
      case 9: return x9
      case 10: return x10
      case 11: return x11
      case 12: return x12
      case 13: return x13
      case 14: return x14
      case 15: return x15
      case 16: return x16
      case 17: return x17
      case 18: return x18
      case 19: return x19
      case 20: return x20
      case 21: return x21
      case 22: return x22
      case 23: return x23
      case 24: return x24
      case 25: return x25
      case 26: return x26
      case 27: return x27
      case 28: return x28
      case 29: return x29
      case 30: return x30
      default: return 0
      }
    }
    set {
      switch index {
      case 0: x0 = newValue
      case 1: x1 = newValue
      case 2: x2 = newValue
      case 3: x3 = newValue
      case 4: x4 = newValue
      case 5: x5 = newValue
      case 6: x6 = newValue
      case 7: x7 = newValue
      case 8: x8 = newValue
      case 9: x9 = newValue
      case 10: x10 = newValue
      case 11: x11 = newValue
      case 12: x12 = newValue
      case 13: x13 = newValue
      case 14: x14 = newValue
      case 15: x15 = newValue
      case 16: x16 = newValue
      case 17: x17 = newValue
      case 18: x18 = newValue
      case 19: x19 = newValue
      case 20: x20 = newValue
      case 21: x21 = newValue
      case 22: x22 = newValue
      case 23: x23 = newValue
      case 24: x24 = newValue
      case 25: x25 = newValue
      case 26: x26 = newValue
      case 27: x27 = newValue
      case 28: x28 = newValue
      case 29: x29 = newValue
      case 30: x30 = newValue
      default: break
      }
    }
  }

  // MARK: - CPSR Flags

  /// Negative flag (bit 31)
  public var negativeFlag: Bool {
    (cpsr & 0x8000_0000) != 0
  }

  /// Zero flag (bit 30)
  public var zeroFlag: Bool {
    (cpsr & 0x4000_0000) != 0
  }

  /// Carry flag (bit 29)
  public var carryFlag: Bool {
    (cpsr & 0x2000_0000) != 0
  }

  /// Overflow flag (bit 28)
  public var overflowFlag: Bool {
    (cpsr & 0x1000_0000) != 0
  }

  /// Human-readable flags description
  public var flagsDescription: String {
    var flags: [String] = []
    if negativeFlag { flags.append("N") }
    if zeroFlag { flags.append("Z") }
    if carryFlag { flags.append("C") }
    if overflowFlag { flags.append("V") }
    return flags.isEmpty ? "----" : flags.joined()
  }

  // MARK: - Constants

  /// Number of general purpose registers (x0-x30)
  public static let generalPurposeCount = 31

  /// Zero register always reads as 0 (xzr in ARM64)
  public static let zeroRegisterValue: UInt64 = 0

  // MARK: - Summary

  /// Brief summary of important registers
  public var summary: String {
    """
    pc  = 0x\(String(pc, radix: 16, uppercase: false).leftPadding(toLength: 16, withPad: "0"))
    sp  = 0x\(String(sp, radix: 16, uppercase: false).leftPadding(toLength: 16, withPad: "0"))
    fp  = 0x\(String(x29, radix: 16, uppercase: false).leftPadding(toLength: 16, withPad: "0"))
    lr  = 0x\(String(x30, radix: 16, uppercase: false).leftPadding(toLength: 16, withPad: "0"))
    """
  }
}

// MARK: - CustomStringConvertible

extension ARM64Registers: CustomStringConvertible {
  public var description: String {
    var lines: [String] = []

    // General purpose registers in groups of 4
    for row in 0..<8 {
      let base = row * 4
      var parts: [String] = []
      for i in 0..<4 {
        let regNum = base + i
        if regNum <= 28 {
          let value = self[regNum]
          parts.append(
            "x\(regNum.description.leftPadding(toLength: 2, withPad: " ")) = 0x\(String(value, radix: 16).leftPadding(toLength: 16, withPad: "0"))"
          )
        }
      }
      if !parts.isEmpty {
        lines.append(parts.joined(separator: "  "))
      }
    }

    // Special registers
    lines.append("")
    lines.append("x29 = 0x\(String(x29, radix: 16).leftPadding(toLength: 16, withPad: "0"))  (fp)")
    lines.append("x30 = 0x\(String(x30, radix: 16).leftPadding(toLength: 16, withPad: "0"))  (lr)")
    lines.append("sp  = 0x\(String(sp, radix: 16).leftPadding(toLength: 16, withPad: "0"))")
    lines.append("pc  = 0x\(String(pc, radix: 16).leftPadding(toLength: 16, withPad: "0"))")
    lines.append(
      "cpsr = 0x\(String(cpsr, radix: 16).leftPadding(toLength: 8, withPad: "0")) [\(flagsDescription)]"
    )

    return lines.joined(separator: "\n")
  }
}

// MARK: - String Extension for Padding

extension String {
  fileprivate func leftPadding(toLength length: Int, withPad pad: String) -> String {
    if self.count >= length {
      return self
    }
    let padding = String(repeating: pad, count: length - self.count)
    return padding + self
  }
}

// MARK: - Mach Thread State Conversion

extension ARM64Registers {

  /// Create registers from Mach thread state
  /// - Parameter state: ARM64 thread state from thread_get_state
  /// - Returns: ARM64Registers populated from the thread state
  #if arch(arm64)
    public static func from(threadState state: arm_thread_state64_t) -> ARM64Registers {
      var regs = ARM64Registers()

      // Manual copy since we can't iterate tuples
      regs.x0 = state.__x.0
      regs.x1 = state.__x.1
      regs.x2 = state.__x.2
      regs.x3 = state.__x.3
      regs.x4 = state.__x.4
      regs.x5 = state.__x.5
      regs.x6 = state.__x.6
      regs.x7 = state.__x.7
      regs.x8 = state.__x.8
      regs.x9 = state.__x.9
      regs.x10 = state.__x.10
      regs.x11 = state.__x.11
      regs.x12 = state.__x.12
      regs.x13 = state.__x.13
      regs.x14 = state.__x.14
      regs.x15 = state.__x.15
      regs.x16 = state.__x.16
      regs.x17 = state.__x.17
      regs.x18 = state.__x.18
      regs.x19 = state.__x.19
      regs.x20 = state.__x.20
      regs.x21 = state.__x.21
      regs.x22 = state.__x.22
      regs.x23 = state.__x.23
      regs.x24 = state.__x.24
      regs.x25 = state.__x.25
      regs.x26 = state.__x.26
      regs.x27 = state.__x.27
      regs.x28 = state.__x.28

      regs.x29 = state.__fp
      regs.x30 = state.__lr
      regs.sp = state.__sp
      regs.pc = state.__pc
      regs.cpsr = state.__cpsr

      return regs
    }

    /// Convert to Mach thread state
    public func toThreadState() -> arm_thread_state64_t {
      var state = arm_thread_state64_t()

      state.__x.0 = x0
      state.__x.1 = x1
      state.__x.2 = x2
      state.__x.3 = x3
      state.__x.4 = x4
      state.__x.5 = x5
      state.__x.6 = x6
      state.__x.7 = x7
      state.__x.8 = x8
      state.__x.9 = x9
      state.__x.10 = x10
      state.__x.11 = x11
      state.__x.12 = x12
      state.__x.13 = x13
      state.__x.14 = x14
      state.__x.15 = x15
      state.__x.16 = x16
      state.__x.17 = x17
      state.__x.18 = x18
      state.__x.19 = x19
      state.__x.20 = x20
      state.__x.21 = x21
      state.__x.22 = x22
      state.__x.23 = x23
      state.__x.24 = x24
      state.__x.25 = x25
      state.__x.26 = x26
      state.__x.27 = x27
      state.__x.28 = x28

      state.__fp = x29
      state.__lr = x30
      state.__sp = sp
      state.__pc = pc
      state.__cpsr = cpsr

      return state
    }
  #endif
}
