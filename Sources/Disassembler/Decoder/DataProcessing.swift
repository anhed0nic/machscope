// DataProcessing.swift
// Disassembler
//
// Data processing instruction decoder (ADD, SUB, MOV, AND, ORR, etc.)

import Foundation

/// Data processing instruction decoder
public struct DataProcessingDecoder: Sendable {

  public init() {}

  // MARK: - Immediate Data Processing

  /// Decode data processing (immediate) instructions
  public func decodeImmediate(_ encoding: UInt32, at address: UInt64) -> Instruction {
    // op0 bits [25:23]
    let op0 = extractBits(encoding, 23, 25)

    switch op0 {
    // PC-rel addressing (ADR, ADRP)
    case 0b000, 0b001:
      return decodePCRelAddressing(encoding, at: address)

    // Add/subtract immediate
    case 0b010, 0b011:
      return decodeAddSubImmediate(encoding, at: address)

    // Logical immediate
    case 0b100:
      return decodeLogicalImmediate(encoding, at: address)

    // Move wide immediate
    case 0b101:
      return decodeMoveWide(encoding, at: address)

    // Bitfield
    case 0b110:
      return decodeBitfield(encoding, at: address)

    // Extract
    case 0b111:
      return decodeExtract(encoding, at: address)

    default:
      return makeUnknown(encoding, at: address)
    }
  }

  // MARK: - Register Data Processing

  /// Decode data processing (register) instructions
  public func decodeRegister(_ encoding: UInt32, at address: UInt64) -> Instruction {
    // Check op1 field bits [28:24]
    let op1 = extractBits(encoding, 24, 28)
    let op2 = extractBits(encoding, 21, 23)

    // Logical (shifted register)
    if extractBit(encoding, 24) == 0 && extractBits(encoding, 21, 23) < 4 {
      return decodeLogicalShiftedRegister(encoding, at: address)
    }

    // Add/subtract (shifted register)
    if op1 == 0b01011 || op1 == 0b11011 {
      return decodeAddSubShiftedRegister(encoding, at: address)
    }

    // Add/subtract (extended register)
    if op1 == 0b01011 && op2 >= 4 {
      return decodeAddSubExtendedRegister(encoding, at: address)
    }

    // Data processing (3 source)
    if extractBits(encoding, 24, 28) == 0b11011 {
      return decodeDataProcessing3Source(encoding, at: address)
    }

    // Data processing (2 source)
    if extractBits(encoding, 24, 28) == 0b11010 && extractBit(encoding, 30) == 1 {
      return decodeDataProcessing2Source(encoding, at: address)
    }

    // Conditional select
    if extractBits(encoding, 21, 28) == 0b11010100 {
      return decodeConditionalSelect(encoding, at: address)
    }

    // Try add/sub shifted register as fallback for common patterns
    if extractBit(encoding, 28) == 0 {
      return decodeAddSubShiftedRegister(encoding, at: address)
    }

    return makeUnknown(encoding, at: address)
  }

  // MARK: - PC-Relative Addressing

  private func decodePCRelAddressing(_ encoding: UInt32, at address: UInt64) -> Instruction {
    let op = extractBit(encoding, 31)
    let immlo = extractBits(encoding, 29, 30)
    let immhi = extractBits(encoding, 5, 23)
    let rd = extractBits(encoding, 0, 4)

    let regD = gprRegister(rd, is64bit: true)

    if op == 0 {
      // ADR
      let imm = (immhi << 2) | immlo
      let target = computeBranchTarget(imm, bits: 21, scale: 1, pc: address)
      return Instruction(
        address: address,
        encoding: encoding,
        mnemonic: "adr",
        operands: [.register(regD), .address(target)],
        category: .loadStore,
        targetAddress: target
      )
    } else {
      // ADRP
      let imm = (immhi << 2) | immlo
      let offset = signExtend(imm, bits: 21) << 12
      let base = address & ~0xFFF  // Page-aligned PC
      let target = UInt64(Int64(base) + offset)
      return Instruction(
        address: address,
        encoding: encoding,
        mnemonic: "adrp",
        operands: [.register(regD), .address(target)],
        category: .loadStore,
        targetAddress: target
      )
    }
  }

  // MARK: - Add/Subtract Immediate

  private func decodeAddSubImmediate(_ encoding: UInt32, at address: UInt64) -> Instruction {
    let sf = extractBit(encoding, 31)  // 64-bit if 1
    let op = extractBit(encoding, 30)  // 0=ADD, 1=SUB
    let s = extractBit(encoding, 29)  // Set flags
    let sh = extractBit(encoding, 22)  // Shift by 12 if 1
    let imm12 = extractBits(encoding, 10, 21)
    let rn = extractBits(encoding, 5, 9)
    let rd = extractBits(encoding, 0, 4)

    let is64bit = sf == 1
    let regD = gprRegister(rd, is64bit: is64bit, allowSP: s == 0)
    let regN = gprRegister(rn, is64bit: is64bit, allowSP: true)

    let immediate = Int64(sh == 1 ? imm12 << 12 : imm12)

    // Determine mnemonic based on op and s
    let baseMnemonic: String
    if op == 0 {
      baseMnemonic = s == 1 ? "adds" : "add"
    } else {
      baseMnemonic = s == 1 ? "subs" : "sub"
    }

    // Check for aliases
    var mnemonic = baseMnemonic
    var operands: [Operand] = [.register(regD), .register(regN), .immediate(immediate)]

    // CMP is SUBS with Rd=xzr/wzr
    if op == 1 && s == 1 && rd == 31 {
      mnemonic = "cmp"
      operands = [.register(regN), .immediate(immediate)]
    }
    // CMN is ADDS with Rd=xzr/wzr
    else if op == 0 && s == 1 && rd == 31 {
      mnemonic = "cmn"
      operands = [.register(regN), .immediate(immediate)]
    }
    // MOV (to/from SP) is ADD with imm=0
    else if op == 0 && s == 0 && imm12 == 0 && sh == 0 && (rn == 31 || rd == 31) {
      mnemonic = "mov"
      operands = [.register(regD), .register(regN)]
    }

    return Instruction(
      address: address,
      encoding: encoding,
      mnemonic: mnemonic,
      operands: operands,
      category: .dataProcessing
    )
  }

  // MARK: - Logical Immediate

  private func decodeLogicalImmediate(_ encoding: UInt32, at address: UInt64) -> Instruction {
    let sf = extractBit(encoding, 31)
    let opc = extractBits(encoding, 29, 30)
    let n = extractBit(encoding, 22)
    let immr = extractBits(encoding, 16, 21)
    let imms = extractBits(encoding, 10, 15)
    let rn = extractBits(encoding, 5, 9)
    let rd = extractBits(encoding, 0, 4)

    let is64bit = sf == 1
    let regD = gprRegister(rd, is64bit: is64bit, allowSP: opc != 0b11)
    let regN = gprRegister(rn, is64bit: is64bit)

    // Decode the bitmask immediate
    let immediate = decodeBitmaskImmediate(n: n, immr: immr, imms: imms, is64bit: is64bit)

    let mnemonic: String
    switch opc {
    case 0b00: mnemonic = "and"
    case 0b01: mnemonic = "orr"
    case 0b10: mnemonic = "eor"
    case 0b11: mnemonic = "ands"
    default: return makeUnknown(encoding, at: address)
    }

    // TST alias: ANDS with Rd=XZR
    if opc == 0b11 && rd == 31 {
      return Instruction(
        address: address,
        encoding: encoding,
        mnemonic: "tst",
        operands: [.register(regN), .immediate(immediate)],
        category: .dataProcessing
      )
    }

    // MOV alias: ORR with Rn=XZR
    if opc == 0b01 && rn == 31 {
      return Instruction(
        address: address,
        encoding: encoding,
        mnemonic: "mov",
        operands: [.register(regD), .immediate(immediate)],
        category: .dataProcessing
      )
    }

    return Instruction(
      address: address,
      encoding: encoding,
      mnemonic: mnemonic,
      operands: [.register(regD), .register(regN), .immediate(immediate)],
      category: .dataProcessing
    )
  }

  // MARK: - Move Wide Immediate

  private func decodeMoveWide(_ encoding: UInt32, at address: UInt64) -> Instruction {
    let sf = extractBit(encoding, 31)
    let opc = extractBits(encoding, 29, 30)
    let hw = extractBits(encoding, 21, 22)
    let imm16 = extractBits(encoding, 5, 20)
    let rd = extractBits(encoding, 0, 4)

    let is64bit = sf == 1
    let regD = gprRegister(rd, is64bit: is64bit)
    let shift = Int(hw * 16)

    let mnemonic: String
    switch opc {
    case 0b00: mnemonic = "movn"
    case 0b10: mnemonic = "movz"
    case 0b11: mnemonic = "movk"
    default: return makeUnknown(encoding, at: address)
    }

    // MOV alias for MOVZ when result can be expressed simply
    if opc == 0b10 && hw == 0 {
      return Instruction(
        address: address,
        encoding: encoding,
        mnemonic: "mov",
        operands: [.register(regD), .immediate(Int64(imm16))],
        category: .dataProcessing
      )
    }

    // MOV alias for MOVN when inverting gives small value
    if opc == 0b00 && hw == 0 && imm16 != 0 {
      let inverted = ~Int64(imm16) & (is64bit ? Int64.max : 0xFFFF_FFFF)
      if inverted >= -65536 && inverted < 65536 {
        return Instruction(
          address: address,
          encoding: encoding,
          mnemonic: "mov",
          operands: [.register(regD), .immediate(inverted)],
          category: .dataProcessing
        )
      }
    }

    var operands: [Operand] = [.register(regD), .immediate(Int64(imm16))]
    if shift != 0 {
      operands.append(.shiftedRegister(register: .xzr, shift: .lsl, amount: shift))
    }

    return Instruction(
      address: address,
      encoding: encoding,
      mnemonic: mnemonic,
      operands: operands,
      category: .dataProcessing
    )
  }

  // MARK: - Bitfield

  private func decodeBitfield(_ encoding: UInt32, at address: UInt64) -> Instruction {
    let sf = extractBit(encoding, 31)
    let opc = extractBits(encoding, 29, 30)
    let immr = extractBits(encoding, 16, 21)
    let imms = extractBits(encoding, 10, 15)
    let rn = extractBits(encoding, 5, 9)
    let rd = extractBits(encoding, 0, 4)

    let is64bit = sf == 1
    let regD = gprRegister(rd, is64bit: is64bit)
    let regN = gprRegister(rn, is64bit: is64bit)
    let regWidth = is64bit ? 64 : 32

    let mnemonic: String
    switch opc {
    case 0b00: mnemonic = "sbfm"
    case 0b01: mnemonic = "bfm"
    case 0b10: mnemonic = "ubfm"
    default: return makeUnknown(encoding, at: address)
    }

    // Check for common aliases
    // ASR alias: SBFM with imms == regWidth-1
    if opc == 0b00 && imms == regWidth - 1 {
      return Instruction(
        address: address,
        encoding: encoding,
        mnemonic: "asr",
        operands: [.register(regD), .register(regN), .immediate(Int64(immr))],
        category: .dataProcessing
      )
    }

    // LSR alias: UBFM with imms == regWidth-1
    if opc == 0b10 && imms == regWidth - 1 {
      return Instruction(
        address: address,
        encoding: encoding,
        mnemonic: "lsr",
        operands: [.register(regD), .register(regN), .immediate(Int64(immr))],
        category: .dataProcessing
      )
    }

    // LSL alias: UBFM with imms+1 == immr
    if opc == 0b10 && imms < regWidth - 1 && immr == (imms + 1) % UInt32(regWidth) {
      let shiftAmount = regWidth - 1 - Int(imms)
      return Instruction(
        address: address,
        encoding: encoding,
        mnemonic: "lsl",
        operands: [.register(regD), .register(regN), .immediate(Int64(shiftAmount))],
        category: .dataProcessing
      )
    }

    // SXTB/SXTH/SXTW aliases
    if opc == 0b00 && immr == 0 {
      if imms == 7 {
        return Instruction(
          address: address,
          encoding: encoding,
          mnemonic: "sxtb",
          operands: [.register(regD), .register(gprRegister(rn, is64bit: false))],
          category: .dataProcessing
        )
      } else if imms == 15 {
        return Instruction(
          address: address,
          encoding: encoding,
          mnemonic: "sxth",
          operands: [.register(regD), .register(gprRegister(rn, is64bit: false))],
          category: .dataProcessing
        )
      } else if imms == 31 && is64bit {
        return Instruction(
          address: address,
          encoding: encoding,
          mnemonic: "sxtw",
          operands: [.register(regD), .register(gprRegister(rn, is64bit: false))],
          category: .dataProcessing
        )
      }
    }

    // UXTB/UXTH aliases
    if opc == 0b10 && immr == 0 {
      if imms == 7 {
        return Instruction(
          address: address,
          encoding: encoding,
          mnemonic: "uxtb",
          operands: [.register(regD), .register(gprRegister(rn, is64bit: false))],
          category: .dataProcessing
        )
      } else if imms == 15 {
        return Instruction(
          address: address,
          encoding: encoding,
          mnemonic: "uxth",
          operands: [.register(regD), .register(gprRegister(rn, is64bit: false))],
          category: .dataProcessing
        )
      }
    }

    return Instruction(
      address: address,
      encoding: encoding,
      mnemonic: mnemonic,
      operands: [
        .register(regD),
        .register(regN),
        .immediate(Int64(immr)),
        .immediate(Int64(imms)),
      ],
      category: .dataProcessing
    )
  }

  // MARK: - Extract

  private func decodeExtract(_ encoding: UInt32, at address: UInt64) -> Instruction {
    let sf = extractBit(encoding, 31)
    let rm = extractBits(encoding, 16, 20)
    let imms = extractBits(encoding, 10, 15)
    let rn = extractBits(encoding, 5, 9)
    let rd = extractBits(encoding, 0, 4)

    let is64bit = sf == 1
    let regD = gprRegister(rd, is64bit: is64bit)
    let regN = gprRegister(rn, is64bit: is64bit)
    let regM = gprRegister(rm, is64bit: is64bit)

    // ROR alias when Rn == Rm
    if rn == rm {
      return Instruction(
        address: address,
        encoding: encoding,
        mnemonic: "ror",
        operands: [.register(regD), .register(regN), .immediate(Int64(imms))],
        category: .dataProcessing
      )
    }

    return Instruction(
      address: address,
      encoding: encoding,
      mnemonic: "extr",
      operands: [.register(regD), .register(regN), .register(regM), .immediate(Int64(imms))],
      category: .dataProcessing
    )
  }

  // MARK: - Logical Shifted Register

  private func decodeLogicalShiftedRegister(_ encoding: UInt32, at address: UInt64) -> Instruction {
    let sf = extractBit(encoding, 31)
    let opc = extractBits(encoding, 29, 30)
    let shift = extractBits(encoding, 22, 23)
    let n = extractBit(encoding, 21)
    let rm = extractBits(encoding, 16, 20)
    let imm6 = extractBits(encoding, 10, 15)
    let rn = extractBits(encoding, 5, 9)
    let rd = extractBits(encoding, 0, 4)

    let is64bit = sf == 1
    let regD = gprRegister(rd, is64bit: is64bit)
    let regN = gprRegister(rn, is64bit: is64bit)
    let regM = gprRegister(rm, is64bit: is64bit)

    let shiftType: ShiftType
    switch shift {
    case 0b00: shiftType = .lsl
    case 0b01: shiftType = .lsr
    case 0b10: shiftType = .asr
    case 0b11: shiftType = .ror
    default: shiftType = .lsl
    }

    let mnemonic: String
    switch (opc, n) {
    case (0b00, 0): mnemonic = "and"
    case (0b00, 1): mnemonic = "bic"
    case (0b01, 0): mnemonic = "orr"
    case (0b01, 1): mnemonic = "orn"
    case (0b10, 0): mnemonic = "eor"
    case (0b10, 1): mnemonic = "eon"
    case (0b11, 0): mnemonic = "ands"
    case (0b11, 1): mnemonic = "bics"
    default: return makeUnknown(encoding, at: address)
    }

    // MOV alias: ORR with Rn=XZR and shift=0
    if opc == 0b01 && n == 0 && rn == 31 && imm6 == 0 {
      return Instruction(
        address: address,
        encoding: encoding,
        mnemonic: "mov",
        operands: [.register(regD), .register(regM)],
        category: .dataProcessing
      )
    }

    // MVN alias: ORN with Rn=XZR
    if opc == 0b01 && n == 1 && rn == 31 {
      if imm6 == 0 {
        return Instruction(
          address: address,
          encoding: encoding,
          mnemonic: "mvn",
          operands: [.register(regD), .register(regM)],
          category: .dataProcessing
        )
      } else {
        return Instruction(
          address: address,
          encoding: encoding,
          mnemonic: "mvn",
          operands: [
            .register(regD), .shiftedRegister(register: regM, shift: shiftType, amount: Int(imm6)),
          ],
          category: .dataProcessing
        )
      }
    }

    // TST alias: ANDS with Rd=XZR
    if opc == 0b11 && n == 0 && rd == 31 {
      if imm6 == 0 {
        return Instruction(
          address: address,
          encoding: encoding,
          mnemonic: "tst",
          operands: [.register(regN), .register(regM)],
          category: .dataProcessing
        )
      } else {
        return Instruction(
          address: address,
          encoding: encoding,
          mnemonic: "tst",
          operands: [
            .register(regN), .shiftedRegister(register: regM, shift: shiftType, amount: Int(imm6)),
          ],
          category: .dataProcessing
        )
      }
    }

    var operands: [Operand] = [.register(regD), .register(regN)]
    if imm6 == 0 {
      operands.append(.register(regM))
    } else {
      operands.append(.shiftedRegister(register: regM, shift: shiftType, amount: Int(imm6)))
    }

    return Instruction(
      address: address,
      encoding: encoding,
      mnemonic: mnemonic,
      operands: operands,
      category: .dataProcessing
    )
  }

  // MARK: - Add/Sub Shifted Register

  private func decodeAddSubShiftedRegister(_ encoding: UInt32, at address: UInt64) -> Instruction {
    let sf = extractBit(encoding, 31)
    let op = extractBit(encoding, 30)
    let s = extractBit(encoding, 29)
    let shift = extractBits(encoding, 22, 23)
    let rm = extractBits(encoding, 16, 20)
    let imm6 = extractBits(encoding, 10, 15)
    let rn = extractBits(encoding, 5, 9)
    let rd = extractBits(encoding, 0, 4)

    let is64bit = sf == 1
    let regD = gprRegister(rd, is64bit: is64bit)
    let regN = gprRegister(rn, is64bit: is64bit)
    let regM = gprRegister(rm, is64bit: is64bit)

    let shiftType: ShiftType
    switch shift {
    case 0b00: shiftType = .lsl
    case 0b01: shiftType = .lsr
    case 0b10: shiftType = .asr
    default: return makeUnknown(encoding, at: address)
    }

    let mnemonic: String
    switch (op, s) {
    case (0, 0): mnemonic = "add"
    case (0, 1): mnemonic = "adds"
    case (1, 0): mnemonic = "sub"
    case (1, 1): mnemonic = "subs"
    default: return makeUnknown(encoding, at: address)
    }

    // CMP alias: SUBS with Rd=XZR
    if op == 1 && s == 1 && rd == 31 {
      if imm6 == 0 {
        return Instruction(
          address: address,
          encoding: encoding,
          mnemonic: "cmp",
          operands: [.register(regN), .register(regM)],
          category: .dataProcessing
        )
      } else {
        return Instruction(
          address: address,
          encoding: encoding,
          mnemonic: "cmp",
          operands: [
            .register(regN), .shiftedRegister(register: regM, shift: shiftType, amount: Int(imm6)),
          ],
          category: .dataProcessing
        )
      }
    }

    // CMN alias: ADDS with Rd=XZR
    if op == 0 && s == 1 && rd == 31 {
      if imm6 == 0 {
        return Instruction(
          address: address,
          encoding: encoding,
          mnemonic: "cmn",
          operands: [.register(regN), .register(regM)],
          category: .dataProcessing
        )
      } else {
        return Instruction(
          address: address,
          encoding: encoding,
          mnemonic: "cmn",
          operands: [
            .register(regN), .shiftedRegister(register: regM, shift: shiftType, amount: Int(imm6)),
          ],
          category: .dataProcessing
        )
      }
    }

    // NEG alias: SUB with Rn=XZR
    if op == 1 && rn == 31 {
      let neg_mnemonic = s == 1 ? "negs" : "neg"
      if imm6 == 0 {
        return Instruction(
          address: address,
          encoding: encoding,
          mnemonic: neg_mnemonic,
          operands: [.register(regD), .register(regM)],
          category: .dataProcessing
        )
      } else {
        return Instruction(
          address: address,
          encoding: encoding,
          mnemonic: neg_mnemonic,
          operands: [
            .register(regD), .shiftedRegister(register: regM, shift: shiftType, amount: Int(imm6)),
          ],
          category: .dataProcessing
        )
      }
    }

    var operands: [Operand] = [.register(regD), .register(regN)]
    if imm6 == 0 {
      operands.append(.register(regM))
    } else {
      operands.append(.shiftedRegister(register: regM, shift: shiftType, amount: Int(imm6)))
    }

    return Instruction(
      address: address,
      encoding: encoding,
      mnemonic: mnemonic,
      operands: operands,
      category: .dataProcessing
    )
  }

  // MARK: - Add/Sub Extended Register

  private func decodeAddSubExtendedRegister(_ encoding: UInt32, at address: UInt64) -> Instruction {
    let sf = extractBit(encoding, 31)
    let op = extractBit(encoding, 30)
    let s = extractBit(encoding, 29)
    let opt = extractBits(encoding, 22, 23)
    let rm = extractBits(encoding, 16, 20)
    let option = extractBits(encoding, 13, 15)
    let imm3 = extractBits(encoding, 10, 12)
    let rn = extractBits(encoding, 5, 9)
    let rd = extractBits(encoding, 0, 4)

    guard opt == 0 else { return makeUnknown(encoding, at: address) }

    let is64bit = sf == 1
    let regD = gprRegister(rd, is64bit: is64bit, allowSP: s == 0)
    let regN = gprRegister(rn, is64bit: is64bit, allowSP: true)

    let extendType: ExtendType
    let rmIs64bit: Bool
    switch option {
    case 0b000:
      extendType = .uxtb
      rmIs64bit = false
    case 0b001:
      extendType = .uxth
      rmIs64bit = false
    case 0b010:
      extendType = .uxtw
      rmIs64bit = false
    case 0b011:
      extendType = .uxtx
      rmIs64bit = true
    case 0b100:
      extendType = .sxtb
      rmIs64bit = false
    case 0b101:
      extendType = .sxth
      rmIs64bit = false
    case 0b110:
      extendType = .sxtw
      rmIs64bit = false
    case 0b111:
      extendType = .sxtx
      rmIs64bit = true
    default: return makeUnknown(encoding, at: address)
    }

    let regM = gprRegister(rm, is64bit: rmIs64bit)

    let mnemonic: String
    switch (op, s) {
    case (0, 0): mnemonic = "add"
    case (0, 1): mnemonic = "adds"
    case (1, 0): mnemonic = "sub"
    case (1, 1): mnemonic = "subs"
    default: return makeUnknown(encoding, at: address)
    }

    return Instruction(
      address: address,
      encoding: encoding,
      mnemonic: mnemonic,
      operands: [
        .register(regD),
        .register(regN),
        .extendedRegister(register: regM, extend: extendType, shift: imm3 == 0 ? nil : Int(imm3)),
      ],
      category: .dataProcessing
    )
  }

  // MARK: - Conditional Select

  private func decodeConditionalSelect(_ encoding: UInt32, at address: UInt64) -> Instruction {
    let sf = extractBit(encoding, 31)
    let op = extractBit(encoding, 30)
    let s = extractBit(encoding, 29)
    let rm = extractBits(encoding, 16, 20)
    let cond = extractBits(encoding, 12, 15)
    let op2 = extractBits(encoding, 10, 11)
    let rn = extractBits(encoding, 5, 9)
    let rd = extractBits(encoding, 0, 4)

    guard s == 0 else { return makeUnknown(encoding, at: address) }

    let is64bit = sf == 1
    let regD = gprRegister(rd, is64bit: is64bit)
    let regN = gprRegister(rn, is64bit: is64bit)
    let regM = gprRegister(rm, is64bit: is64bit)

    guard let condCode = ConditionCode(code: Int(cond)) else {
      return makeUnknown(encoding, at: address)
    }

    let mnemonic: String
    switch (op, op2) {
    case (0, 0b00): mnemonic = "csel"
    case (0, 0b01): mnemonic = "csinc"
    case (1, 0b00): mnemonic = "csinv"
    case (1, 0b01): mnemonic = "csneg"
    default: return makeUnknown(encoding, at: address)
    }

    // CSET alias: CSINC with Rn=Rm=XZR
    if op == 0 && op2 == 0b01 && rn == 31 && rm == 31 {
      let invertedCond = ConditionCode(code: Int(cond) ^ 1) ?? condCode
      return Instruction(
        address: address,
        encoding: encoding,
        mnemonic: "cset",
        operands: [.register(regD), .condition(invertedCond)],
        category: .dataProcessing
      )
    }

    // CSETM alias: CSINV with Rn=Rm=XZR
    if op == 1 && op2 == 0b00 && rn == 31 && rm == 31 {
      let invertedCond = ConditionCode(code: Int(cond) ^ 1) ?? condCode
      return Instruction(
        address: address,
        encoding: encoding,
        mnemonic: "csetm",
        operands: [.register(regD), .condition(invertedCond)],
        category: .dataProcessing
      )
    }

    // CINC alias: CSINC with Rn=Rm
    if op == 0 && op2 == 0b01 && rn == rm && rn != 31 {
      let invertedCond = ConditionCode(code: Int(cond) ^ 1) ?? condCode
      return Instruction(
        address: address,
        encoding: encoding,
        mnemonic: "cinc",
        operands: [.register(regD), .register(regN), .condition(invertedCond)],
        category: .dataProcessing
      )
    }

    return Instruction(
      address: address,
      encoding: encoding,
      mnemonic: mnemonic,
      operands: [.register(regD), .register(regN), .register(regM), .condition(condCode)],
      category: .dataProcessing
    )
  }

  // MARK: - Data Processing (2 source)

  private func decodeDataProcessing2Source(_ encoding: UInt32, at address: UInt64) -> Instruction {
    let sf = extractBit(encoding, 31)
    let rm = extractBits(encoding, 16, 20)
    let opcode = extractBits(encoding, 10, 15)
    let rn = extractBits(encoding, 5, 9)
    let rd = extractBits(encoding, 0, 4)

    let is64bit = sf == 1
    let regD = gprRegister(rd, is64bit: is64bit)
    let regN = gprRegister(rn, is64bit: is64bit)
    let regM = gprRegister(rm, is64bit: is64bit)

    let mnemonic: String
    switch opcode {
    case 0b000010: mnemonic = "udiv"
    case 0b000011: mnemonic = "sdiv"
    case 0b001000: mnemonic = "lslv"
    case 0b001001: mnemonic = "lsrv"
    case 0b001010: mnemonic = "asrv"
    case 0b001011: mnemonic = "rorv"
    default: return makeUnknown(encoding, at: address)
    }

    // Use simpler aliases
    let finalMnemonic: String
    switch mnemonic {
    case "lslv": finalMnemonic = "lsl"
    case "lsrv": finalMnemonic = "lsr"
    case "asrv": finalMnemonic = "asr"
    case "rorv": finalMnemonic = "ror"
    default: finalMnemonic = mnemonic
    }

    return Instruction(
      address: address,
      encoding: encoding,
      mnemonic: finalMnemonic,
      operands: [.register(regD), .register(regN), .register(regM)],
      category: .dataProcessing
    )
  }

  // MARK: - Data Processing (3 source)

  private func decodeDataProcessing3Source(_ encoding: UInt32, at address: UInt64) -> Instruction {
    let sf = extractBit(encoding, 31)
    let op54 = extractBits(encoding, 29, 30)
    let op31 = extractBits(encoding, 21, 23)
    let rm = extractBits(encoding, 16, 20)
    let o0 = extractBit(encoding, 15)
    let ra = extractBits(encoding, 10, 14)
    let rn = extractBits(encoding, 5, 9)
    let rd = extractBits(encoding, 0, 4)

    guard op54 == 0 else { return makeUnknown(encoding, at: address) }

    let is64bit = sf == 1
    let regD = gprRegister(rd, is64bit: is64bit)
    let regN = gprRegister(rn, is64bit: is64bit)
    let regM = gprRegister(rm, is64bit: is64bit)
    let regA = gprRegister(ra, is64bit: is64bit)

    let mnemonic: String
    switch (op31, o0) {
    case (0b000, 0): mnemonic = "madd"
    case (0b000, 1): mnemonic = "msub"
    case (0b001, 0) where sf == 1: mnemonic = "smaddl"
    case (0b001, 1) where sf == 1: mnemonic = "smsubl"
    case (0b010, 0) where sf == 1: mnemonic = "smulh"
    case (0b101, 0) where sf == 1: mnemonic = "umaddl"
    case (0b101, 1) where sf == 1: mnemonic = "umsubl"
    case (0b110, 0) where sf == 1: mnemonic = "umulh"
    default: return makeUnknown(encoding, at: address)
    }

    // MUL alias: MADD with Ra=XZR
    if mnemonic == "madd" && ra == 31 {
      return Instruction(
        address: address,
        encoding: encoding,
        mnemonic: "mul",
        operands: [.register(regD), .register(regN), .register(regM)],
        category: .dataProcessing
      )
    }

    // MNEG alias: MSUB with Ra=XZR
    if mnemonic == "msub" && ra == 31 {
      return Instruction(
        address: address,
        encoding: encoding,
        mnemonic: "mneg",
        operands: [.register(regD), .register(regN), .register(regM)],
        category: .dataProcessing
      )
    }

    // SMULL/UMULL aliases
    if (mnemonic == "smaddl" || mnemonic == "umaddl") && ra == 31 {
      let alias = mnemonic == "smaddl" ? "smull" : "umull"
      return Instruction(
        address: address,
        encoding: encoding,
        mnemonic: alias,
        operands: [
          .register(regD), .register(gprRegister(rn, is64bit: false)),
          .register(gprRegister(rm, is64bit: false)),
        ],
        category: .dataProcessing
      )
    }

    return Instruction(
      address: address,
      encoding: encoding,
      mnemonic: mnemonic,
      operands: [.register(regD), .register(regN), .register(regM), .register(regA)],
      category: .dataProcessing
    )
  }

  // MARK: - Helpers

  private func makeUnknown(_ encoding: UInt32, at address: UInt64) -> Instruction {
    Instruction(
      address: address,
      encoding: encoding,
      mnemonic: ".word",
      operands: [.immediate(Int64(encoding))],
      category: .unknown
    )
  }

  /// Decode ARM64 bitmask immediate (complex encoding)
  private func decodeBitmaskImmediate(n: UInt32, immr: UInt32, imms: UInt32, is64bit: Bool) -> Int64
  {
    // This is a simplified version - full decoding is complex
    // For now, just return the raw immediate value
    let combined = (n << 12) | (immr << 6) | imms
    return Int64(combined)
  }
}
