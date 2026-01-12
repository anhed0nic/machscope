// Instruction.swift
// Disassembler
//
// Decoded ARM64 instruction model with operands

import Foundation

// MARK: - Instruction Category

/// Instruction category
public enum InstructionCategory: String, Sendable, Codable {
  case dataProcessing
  case branch
  case loadStore
  case system
  case simd
  case pac  // Pointer authentication
  case unknown
}

// MARK: - Register Types

/// ARM64 register width
public enum RegisterWidth: String, Sendable, Codable {
  case w = "w"  // 32-bit
  case x = "x"  // 64-bit
  case b = "b"  // 8-bit SIMD
  case h = "h"  // 16-bit SIMD
  case s = "s"  // 32-bit SIMD/FP
  case d = "d"  // 64-bit SIMD/FP
  case q = "q"  // 128-bit SIMD
}

/// ARM64 register
public enum Register: Sendable, Codable, Equatable {
  /// General purpose register (x0-x30/w0-w30)
  case general(Int, RegisterWidth)

  /// Stack pointer
  case sp

  /// Zero register (xzr/wzr)
  case xzr
  case wzr

  /// Program counter (for PC-relative addressing)
  case pc

  /// SIMD/FP register
  case simd(Int, RegisterWidth)

  /// System register by name
  case system(String)

  /// Display name for the register
  public var name: String {
    switch self {
    case .general(let num, let width):
      // x29 = fp, x30 = lr
      if num == 29 && width == .x {
        return "x29"  // or "fp"
      } else if num == 30 && width == .x {
        return "x30"  // or "lr"
      }
      return "\(width.rawValue)\(num)"
    case .sp:
      return "sp"
    case .xzr:
      return "xzr"
    case .wzr:
      return "wzr"
    case .pc:
      return "pc"
    case .simd(let num, let width):
      return "\(width.rawValue)\(num)"
    case .system(let name):
      return name
    }
  }
}

// MARK: - Memory Index Mode

/// Memory access index mode
public enum MemoryIndexMode: String, Sendable, Codable {
  case offset  // [base, #imm]
  case preIndex  // [base, #imm]!
  case postIndex  // [base], #imm
  case register  // [base, Xm]
}

// MARK: - Shift Type

/// Shift type for shifted registers
public enum ShiftType: String, Sendable, Codable {
  case lsl = "lsl"  // Logical shift left
  case lsr = "lsr"  // Logical shift right
  case asr = "asr"  // Arithmetic shift right
  case ror = "ror"  // Rotate right
}

// MARK: - Extend Type

/// Extend type for extended registers
public enum ExtendType: String, Sendable, Codable {
  case uxtb = "uxtb"  // Unsigned extend byte
  case uxth = "uxth"  // Unsigned extend halfword
  case uxtw = "uxtw"  // Unsigned extend word
  case uxtx = "uxtx"  // Unsigned extend doubleword
  case sxtb = "sxtb"  // Signed extend byte
  case sxth = "sxth"  // Signed extend halfword
  case sxtw = "sxtw"  // Signed extend word
  case sxtx = "sxtx"  // Signed extend doubleword
}

// MARK: - Condition Code

/// ARM64 condition codes
public enum ConditionCode: String, Sendable, Codable {
  case eq = "eq"  // Equal (Z=1)
  case ne = "ne"  // Not equal (Z=0)
  case cs = "cs"  // Carry set / unsigned higher or same (C=1)
  case cc = "cc"  // Carry clear / unsigned lower (C=0)
  case mi = "mi"  // Minus / negative (N=1)
  case pl = "pl"  // Plus / positive or zero (N=0)
  case vs = "vs"  // Overflow (V=1)
  case vc = "vc"  // No overflow (V=0)
  case hi = "hi"  // Unsigned higher (C=1 && Z=0)
  case ls = "ls"  // Unsigned lower or same (C=0 || Z=1)
  case ge = "ge"  // Signed greater than or equal (N==V)
  case lt = "lt"  // Signed less than (N!=V)
  case gt = "gt"  // Signed greater than (Z=0 && N==V)
  case le = "le"  // Signed less than or equal (Z=1 || N!=V)
  case al = "al"  // Always (unconditional)
  case nv = "nv"  // Never (reserved)

  /// Create from 4-bit condition code
  public init?(code: Int) {
    switch code & 0xF {
    case 0: self = .eq
    case 1: self = .ne
    case 2: self = .cs
    case 3: self = .cc
    case 4: self = .mi
    case 5: self = .pl
    case 6: self = .vs
    case 7: self = .vc
    case 8: self = .hi
    case 9: self = .ls
    case 10: self = .ge
    case 11: self = .lt
    case 12: self = .gt
    case 13: self = .le
    case 14: self = .al
    case 15: self = .nv
    default: return nil
    }
  }
}

// MARK: - Operand

/// Instruction operand
public enum Operand: Sendable, Codable, Equatable {
  /// Register operand
  case register(Register)

  /// Immediate value
  case immediate(Int64)

  /// Address (for branches, PC-relative)
  case address(UInt64)

  /// Memory operand with base register, offset, and index mode
  case memory(base: Register, offset: Int64, indexMode: MemoryIndexMode)

  /// Memory operand with base and index registers
  case memoryRegister(base: Register, index: Register, extend: ExtendType?, shift: Int?)

  /// Shifted register
  case shiftedRegister(register: Register, shift: ShiftType, amount: Int)

  /// Extended register
  case extendedRegister(register: Register, extend: ExtendType, shift: Int?)

  /// Condition code
  case condition(ConditionCode)

  /// Label (symbolic name)
  case label(String)

  /// System register name
  case systemRegister(String)

  /// Barrier option
  case barrier(String)

  /// Prefetch operation
  case prefetch(String)
}

// MARK: - Instruction

/// Decoded ARM64 instruction
public struct Instruction: Sendable, Codable {
  /// Virtual address
  public let address: UInt64

  /// Raw instruction bytes
  public let encoding: UInt32

  /// Instruction mnemonic
  public let mnemonic: String

  /// Instruction operands
  public let operands: [Operand]

  /// Instruction category
  public let category: InstructionCategory

  /// Optional annotation (e.g., PAC info)
  public let annotation: String?

  /// Branch/call target address
  public let targetAddress: UInt64?

  /// Resolved symbol name
  public let targetSymbol: String?

  /// Creates an instruction with all fields
  public init(
    address: UInt64,
    encoding: UInt32,
    mnemonic: String,
    operands: [Operand] = [],
    category: InstructionCategory,
    annotation: String? = nil,
    targetAddress: UInt64? = nil,
    targetSymbol: String? = nil
  ) {
    self.address = address
    self.encoding = encoding
    self.mnemonic = mnemonic
    self.operands = operands
    self.category = category
    self.annotation = annotation
    self.targetAddress = targetAddress
    self.targetSymbol = targetSymbol
  }

  /// Creates a copy with updated annotation
  public func withAnnotation(_ annotation: String?) -> Instruction {
    Instruction(
      address: address,
      encoding: encoding,
      mnemonic: mnemonic,
      operands: operands,
      category: category,
      annotation: annotation,
      targetAddress: targetAddress,
      targetSymbol: targetSymbol
    )
  }

  /// Creates a copy with updated target symbol
  public func withTargetSymbol(_ symbol: String?) -> Instruction {
    Instruction(
      address: address,
      encoding: encoding,
      mnemonic: mnemonic,
      operands: operands,
      category: category,
      annotation: annotation,
      targetAddress: targetAddress,
      targetSymbol: symbol
    )
  }

  /// Creates a copy with updated category
  public func withCategory(_ category: InstructionCategory) -> Instruction {
    Instruction(
      address: address,
      encoding: encoding,
      mnemonic: mnemonic,
      operands: operands,
      category: category,
      annotation: annotation,
      targetAddress: targetAddress,
      targetSymbol: targetSymbol
    )
  }
}

// MARK: - CustomStringConvertible

extension Instruction: CustomStringConvertible {
  public var description: String {
    var result = "\(String(format: "0x%llx", address)): \(mnemonic)"

    if !operands.isEmpty {
      let operandStrings = operands.map { operandDescription($0) }
      result += " " + operandStrings.joined(separator: ", ")
    }

    if let symbol = targetSymbol {
      result += " ; \(symbol)"
    }

    if let annotation = annotation {
      result += " ; \(annotation)"
    }

    return result
  }

  private func operandDescription(_ operand: Operand) -> String {
    switch operand {
    case .register(let reg):
      return reg.name
    case .immediate(let value):
      if value < 0 {
        return "#-0x\(String(-value, radix: 16))"
      } else {
        return "#0x\(String(value, radix: 16))"
      }
    case .address(let addr):
      return "0x\(String(addr, radix: 16))"
    case .memory(let base, let offset, let mode):
      switch mode {
      case .offset:
        if offset == 0 {
          return "[\(base.name)]"
        }
        return "[\(base.name), #\(offset)]"
      case .preIndex:
        return "[\(base.name), #\(offset)]!"
      case .postIndex:
        return "[\(base.name)], #\(offset)"
      case .register:
        return "[\(base.name)]"
      }
    case .memoryRegister(let base, let index, let extend, let shift):
      var result = "[\(base.name), \(index.name)"
      if let ext = extend {
        result += ", \(ext.rawValue)"
        if let s = shift, s != 0 {
          result += " #\(s)"
        }
      }
      result += "]"
      return result
    case .shiftedRegister(let reg, let shift, let amount):
      if amount == 0 {
        return reg.name
      }
      return "\(reg.name), \(shift.rawValue) #\(amount)"
    case .extendedRegister(let reg, let extend, let shift):
      var result = "\(reg.name), \(extend.rawValue)"
      if let s = shift, s != 0 {
        result += " #\(s)"
      }
      return result
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
}
