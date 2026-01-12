// System.swift
// Disassembler
//
// System instruction decoder (SVC, NOP, PAC instructions, barriers)

import Foundation

/// System instruction decoder
public struct SystemDecoder: Sendable {

  public init() {}

  // MARK: - Exception Generating

  /// Decode exception generating instructions (SVC, HVC, SMC, BRK, HLT)
  public func decodeException(_ encoding: UInt32, at address: UInt64) -> Instruction {
    let opc = extractBits(encoding, 21, 23)
    let imm16 = extractBits(encoding, 5, 20)
    let op2 = extractBits(encoding, 2, 4)
    let ll = extractBits(encoding, 0, 1)

    switch (opc, op2, ll) {
    // SVC #imm
    case (0b000, 0b000, 0b01):
      return Instruction(
        address: address,
        encoding: encoding,
        mnemonic: "svc",
        operands: [.immediate(Int64(imm16))],
        category: .system
      )

    // HVC #imm
    case (0b000, 0b000, 0b10):
      return Instruction(
        address: address,
        encoding: encoding,
        mnemonic: "hvc",
        operands: [.immediate(Int64(imm16))],
        category: .system
      )

    // SMC #imm
    case (0b000, 0b000, 0b11):
      return Instruction(
        address: address,
        encoding: encoding,
        mnemonic: "smc",
        operands: [.immediate(Int64(imm16))],
        category: .system
      )

    // BRK #imm
    case (0b001, 0b000, 0b00):
      return Instruction(
        address: address,
        encoding: encoding,
        mnemonic: "brk",
        operands: [.immediate(Int64(imm16))],
        category: .system
      )

    // HLT #imm
    case (0b010, 0b000, 0b00):
      return Instruction(
        address: address,
        encoding: encoding,
        mnemonic: "hlt",
        operands: [.immediate(Int64(imm16))],
        category: .system
      )

    // DCPS1
    case (0b101, 0b000, 0b01):
      return Instruction(
        address: address,
        encoding: encoding,
        mnemonic: "dcps1",
        operands: imm16 != 0 ? [.immediate(Int64(imm16))] : [],
        category: .system
      )

    // DCPS2
    case (0b101, 0b000, 0b10):
      return Instruction(
        address: address,
        encoding: encoding,
        mnemonic: "dcps2",
        operands: imm16 != 0 ? [.immediate(Int64(imm16))] : [],
        category: .system
      )

    // DCPS3
    case (0b101, 0b000, 0b11):
      return Instruction(
        address: address,
        encoding: encoding,
        mnemonic: "dcps3",
        operands: imm16 != 0 ? [.immediate(Int64(imm16))] : [],
        category: .system
      )

    default:
      return makeUnknown(encoding, at: address)
    }
  }

  // MARK: - System Instructions

  /// Decode system instructions (MSR, MRS, SYS, SYSL, NOP, hints, barriers)
  public func decodeSystem(_ encoding: UInt32, at address: UInt64) -> Instruction {
    let l = extractBit(encoding, 21)
    let op0 = extractBits(encoding, 19, 20)
    let op1 = extractBits(encoding, 16, 18)
    let crn = extractBits(encoding, 12, 15)
    let crm = extractBits(encoding, 8, 11)
    let op2 = extractBits(encoding, 5, 7)
    let rt = extractBits(encoding, 0, 4)

    // Check for hints (NOP, YIELD, WFE, WFI, SEV, SEVL, etc.)
    if l == 0 && op0 == 0b00 && op1 == 0b011 && crn == 0b0010 && rt == 0b11111 {
      return decodeHint(encoding, at: address, crm: crm, op2: op2)
    }

    // Check for barriers (CLREX, DSB, DMB, ISB)
    if l == 0 && op0 == 0b00 && op1 == 0b011 && crn == 0b0011 && rt == 0b11111 {
      return decodeBarrier(encoding, at: address, crm: crm, op2: op2)
    }

    // MSR (immediate) - PSTATE
    if l == 0 && op0 == 0b00 && (crn == 0b0100 || crn == 0b0001) {
      return decodeMSRImmediate(encoding, at: address, op1: op1, crm: crm, op2: op2)
    }

    // MSR/MRS (register)
    if op0 != 0b00 {
      let sysRegName = formatSystemRegister(op0: op0, op1: op1, crn: crn, crm: crm, op2: op2)
      let reg = gprRegister(rt, is64bit: true)

      if l == 0 {
        // MSR
        return Instruction(
          address: address,
          encoding: encoding,
          mnemonic: "msr",
          operands: [.systemRegister(sysRegName), .register(reg)],
          category: .system
        )
      } else {
        // MRS
        return Instruction(
          address: address,
          encoding: encoding,
          mnemonic: "mrs",
          operands: [.register(reg), .systemRegister(sysRegName)],
          category: .system
        )
      }
    }

    // SYS/SYSL
    if op0 == 0b01 {
      let reg = rt == 31 ? nil : gprRegister(rt, is64bit: true)

      if l == 0 {
        var operands: [Operand] = [
          .immediate(Int64(op1)),
          .systemRegister("C\(crn)"),
          .systemRegister("C\(crm)"),
          .immediate(Int64(op2)),
        ]
        if let r = reg {
          operands.append(.register(r))
        }
        return Instruction(
          address: address,
          encoding: encoding,
          mnemonic: "sys",
          operands: operands,
          category: .system
        )
      } else {
        var operands: [Operand] = []
        if let r = reg {
          operands.append(.register(r))
        }
        operands.append(contentsOf: [
          .immediate(Int64(op1)),
          .systemRegister("C\(crn)"),
          .systemRegister("C\(crm)"),
          .immediate(Int64(op2)),
        ])
        return Instruction(
          address: address,
          encoding: encoding,
          mnemonic: "sysl",
          operands: operands,
          category: .system
        )
      }
    }

    return makeUnknown(encoding, at: address)
  }

  // MARK: - Hints

  private func decodeHint(_ encoding: UInt32, at address: UInt64, crm: UInt32, op2: UInt32)
    -> Instruction
  {
    let hint = (crm << 3) | op2

    let mnemonic: String
    switch hint {
    case 0b0000000: mnemonic = "nop"
    case 0b0000001: mnemonic = "yield"
    case 0b0000010: mnemonic = "wfe"
    case 0b0000011: mnemonic = "wfi"
    case 0b0000100: mnemonic = "sev"
    case 0b0000101: mnemonic = "sevl"
    case 0b0000110: mnemonic = "dgh"
    case 0b0000111: mnemonic = "xpaclri"
    // PAC hints
    case 0b0001000: mnemonic = "pacia1716"
    case 0b0001010: mnemonic = "pacib1716"
    case 0b0001100: mnemonic = "autia1716"
    case 0b0001110: mnemonic = "autib1716"
    case 0b0011000: mnemonic = "paciaz"
    case 0b0011001: mnemonic = "paciasp"
    case 0b0011010: mnemonic = "pacibz"
    case 0b0011011: mnemonic = "pacibsp"
    case 0b0011100: mnemonic = "autiaz"
    case 0b0011101: mnemonic = "autiasp"
    case 0b0011110: mnemonic = "autibz"
    case 0b0011111: mnemonic = "autibsp"
    // Branch target identification
    case 0b0100000: mnemonic = "bti"
    case 0b0100010: mnemonic = "bti c"
    case 0b0100100: mnemonic = "bti j"
    case 0b0100110: mnemonic = "bti jc"
    // Memory tagging
    case 0b0010000: mnemonic = "esb"
    case 0b0010001: mnemonic = "psb csync"
    case 0b0010010: mnemonic = "tsb csync"
    case 0b0010100: mnemonic = "csdb"
    default:
      mnemonic = "hint"
      return Instruction(
        address: address,
        encoding: encoding,
        mnemonic: mnemonic,
        operands: [.immediate(Int64(hint))],
        category: .system
      )
    }

    // Check if this is a PAC instruction
    let isPAC = mnemonic.hasPrefix("pac") || mnemonic.hasPrefix("aut") || mnemonic == "xpaclri"
    let category: InstructionCategory = isPAC ? .pac : .system

    return Instruction(
      address: address,
      encoding: encoding,
      mnemonic: mnemonic,
      operands: [],
      category: category,
      annotation: isPAC ? "[PAC] Hint instruction" : nil
    )
  }

  // MARK: - Barriers

  private func decodeBarrier(_ encoding: UInt32, at address: UInt64, crm: UInt32, op2: UInt32)
    -> Instruction
  {
    let mnemonic: String
    let barrierOption: String?

    switch op2 {
    case 0b010:
      // CLREX
      mnemonic = "clrex"
      barrierOption = crm != 0b1111 ? "#\(crm)" : nil

    case 0b100:
      // DSB
      mnemonic = "dsb"
      barrierOption = barrierOptionName(crm)

    case 0b101:
      // DMB
      mnemonic = "dmb"
      barrierOption = barrierOptionName(crm)

    case 0b110:
      // ISB
      mnemonic = "isb"
      barrierOption = crm != 0b1111 ? "#\(crm)" : nil

    case 0b111:
      // SB
      mnemonic = "sb"
      barrierOption = nil

    default:
      return makeUnknown(encoding, at: address)
    }

    var operands: [Operand] = []
    if let opt = barrierOption {
      operands.append(.barrier(opt))
    }

    return Instruction(
      address: address,
      encoding: encoding,
      mnemonic: mnemonic,
      operands: operands,
      category: .system
    )
  }

  private func barrierOptionName(_ crm: UInt32) -> String {
    switch crm {
    case 0b0001: return "oshld"
    case 0b0010: return "oshst"
    case 0b0011: return "osh"
    case 0b0101: return "nshld"
    case 0b0110: return "nshst"
    case 0b0111: return "nsh"
    case 0b1001: return "ishld"
    case 0b1010: return "ishst"
    case 0b1011: return "ish"
    case 0b1101: return "ld"
    case 0b1110: return "st"
    case 0b1111: return "sy"
    default: return "#\(crm)"
    }
  }

  // MARK: - MSR Immediate

  private func decodeMSRImmediate(
    _ encoding: UInt32, at address: UInt64, op1: UInt32, crm: UInt32, op2: UInt32
  ) -> Instruction {
    let pstateName: String

    switch (op1, op2) {
    case (0b000, 0b101): pstateName = "spsel"
    case (0b011, 0b110): pstateName = "daifset"
    case (0b011, 0b111): pstateName = "daifclr"
    case (0b000, 0b011): pstateName = "uao"
    case (0b000, 0b100): pstateName = "pan"
    case (0b001, 0b000): pstateName = "allint"
    default: pstateName = "pstate_\(op1)_\(op2)"
    }

    return Instruction(
      address: address,
      encoding: encoding,
      mnemonic: "msr",
      operands: [.systemRegister(pstateName), .immediate(Int64(crm))],
      category: .system
    )
  }

  // MARK: - Helpers

  private func formatSystemRegister(op0: UInt32, op1: UInt32, crn: UInt32, crm: UInt32, op2: UInt32)
    -> String
  {
    // Common system registers
    let key = (op0, op1, crn, crm, op2)

    switch key {
    case (3, 3, 4, 2, 0): return "nzcv"
    case (3, 3, 4, 2, 1): return "daif"
    case (3, 0, 4, 0, 1): return "elr_el1"
    case (3, 0, 4, 0, 0): return "spsr_el1"
    case (3, 3, 4, 4, 0): return "fpcr"
    case (3, 3, 4, 4, 1): return "fpsr"
    case (3, 0, 4, 1, 0): return "sp_el0"
    case (3, 0, 4, 2, 2): return "currentel"
    case (3, 3, 13, 0, 2): return "tpidr_el0"
    case (3, 3, 13, 0, 3): return "tpidrro_el0"
    case (3, 0, 0, 0, 0): return "midr_el1"
    case (3, 0, 0, 0, 5): return "mpidr_el1"
    case (3, 0, 1, 0, 0): return "sctlr_el1"
    case (3, 0, 2, 0, 0): return "ttbr0_el1"
    case (3, 0, 2, 0, 1): return "ttbr1_el1"
    case (3, 0, 2, 0, 2): return "tcr_el1"
    case (3, 0, 5, 1, 0): return "afsr0_el1"
    case (3, 0, 5, 1, 1): return "afsr1_el1"
    case (3, 0, 5, 2, 0): return "esr_el1"
    case (3, 0, 6, 0, 0): return "far_el1"
    case (3, 0, 10, 2, 0): return "mair_el1"
    case (3, 0, 12, 0, 0): return "vbar_el1"
    case (3, 0, 13, 0, 1): return "contextidr_el1"
    case (3, 0, 13, 0, 4): return "tpidr_el1"
    case (3, 0, 14, 1, 0): return "cntkctl_el1"
    case (3, 3, 14, 0, 0): return "cntfrq_el0"
    case (3, 3, 14, 0, 1): return "cntpct_el0"
    case (3, 3, 14, 0, 2): return "cntvct_el0"
    case (3, 3, 14, 2, 0): return "cntp_tval_el0"
    case (3, 3, 14, 2, 1): return "cntp_ctl_el0"
    case (3, 3, 14, 2, 2): return "cntp_cval_el0"
    case (3, 3, 14, 3, 0): return "cntv_tval_el0"
    case (3, 3, 14, 3, 1): return "cntv_ctl_el0"
    case (3, 3, 14, 3, 2): return "cntv_cval_el0"
    default:
      return "s\(op0)_\(op1)_c\(crn)_c\(crm)_\(op2)"
    }
  }

  private func makeUnknown(_ encoding: UInt32, at address: UInt64) -> Instruction {
    Instruction(
      address: address,
      encoding: encoding,
      mnemonic: ".word",
      operands: [.immediate(Int64(encoding))],
      category: .unknown
    )
  }
}
