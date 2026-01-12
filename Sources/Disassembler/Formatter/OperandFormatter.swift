// OperandFormatter.swift
// Disassembler
//
// Operand display formatter for ARM64 assembly

import Foundation

/// Operand formatter for ARM64 assembly notation
public struct OperandFormatter: Sendable {

  public init() {}

  /// Format an operand for display
  /// - Parameter operand: The operand to format
  /// - Returns: Formatted string
  public func format(_ operand: Operand) -> String {
    switch operand {
    case .register(let reg):
      return formatRegister(reg)

    case .immediate(let value):
      return formatImmediate(value)

    case .address(let addr):
      return formatAddress(addr)

    case .memory(let base, let offset, let mode):
      return formatMemory(base: base, offset: offset, mode: mode)

    case .memoryRegister(let base, let index, let extend, let shift):
      return formatMemoryRegister(base: base, index: index, extend: extend, shift: shift)

    case .shiftedRegister(let reg, let shift, let amount):
      return formatShiftedRegister(reg: reg, shift: shift, amount: amount)

    case .extendedRegister(let reg, let extend, let shift):
      return formatExtendedRegister(reg: reg, extend: extend, shift: shift)

    case .condition(let cond):
      return cond.rawValue

    case .label(let name):
      return name

    case .systemRegister(let name):
      return name

    case .barrier(let option):
      return option

    case .prefetch(let op):
      return op
    }
  }

  // MARK: - Private Formatters

  private func formatRegister(_ reg: Register) -> String {
    reg.name
  }

  private func formatImmediate(_ value: Int64) -> String {
    if value < 0 {
      return "#-0x\(String(-value, radix: 16))"
    } else if value < 16 {
      return "#\(value)"
    } else {
      return "#0x\(String(value, radix: 16))"
    }
  }

  private func formatAddress(_ addr: UInt64) -> String {
    "0x\(String(addr, radix: 16))"
  }

  private func formatMemory(base: Register, offset: Int64, mode: MemoryIndexMode) -> String {
    let baseStr = formatRegister(base)

    switch mode {
    case .offset:
      if offset == 0 {
        return "[\(baseStr)]"
      }
      let offsetStr = formatOffset(offset)
      return "[\(baseStr), \(offsetStr)]"

    case .preIndex:
      let offsetStr = formatOffset(offset)
      return "[\(baseStr), \(offsetStr)]!"

    case .postIndex:
      let offsetStr = formatOffset(offset)
      return "[\(baseStr)], \(offsetStr)"

    case .register:
      return "[\(baseStr)]"
    }
  }

  private func formatMemoryRegister(
    base: Register, index: Register, extend: ExtendType?, shift: Int?
  ) -> String {
    let baseStr = formatRegister(base)
    let indexStr = formatRegister(index)

    var parts = [baseStr, indexStr]

    if let ext = extend {
      var extStr = ext.rawValue
      if let s = shift, s != 0 {
        extStr += " #\(s)"
      }
      parts.append(extStr)
    } else if let s = shift, s != 0 {
      parts.append("lsl #\(s)")
    }

    return "[\(parts.joined(separator: ", "))]"
  }

  private func formatShiftedRegister(reg: Register, shift: ShiftType, amount: Int) -> String {
    let regStr = formatRegister(reg)

    if amount == 0 {
      return regStr
    }

    return "\(regStr), \(shift.rawValue) #\(amount)"
  }

  private func formatExtendedRegister(reg: Register, extend: ExtendType, shift: Int?) -> String {
    let regStr = formatRegister(reg)

    if let s = shift, s != 0 {
      return "\(regStr), \(extend.rawValue) #\(s)"
    }

    return "\(regStr), \(extend.rawValue)"
  }

  private func formatOffset(_ offset: Int64) -> String {
    if offset < 0 {
      return "#-0x\(String(-offset, radix: 16))"
    } else if offset == 0 {
      return "#0"
    } else if offset < 16 {
      return "#\(offset)"
    } else {
      return "#0x\(String(offset, radix: 16))"
    }
  }
}
