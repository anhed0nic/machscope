// LoadStore.swift
// Disassembler
//
// Load/Store instruction decoder (LDR, STR, LDP, STP, etc.)

import Foundation

/// Load/Store instruction decoder
public struct LoadStoreDecoder: Sendable {

  public init() {}

  /// Main decode entry point
  public func decode(_ encoding: UInt32, at address: UInt64) -> Instruction {
    // Check for literal load (LDR literal)
    if extractBits(encoding, 27, 29) == 0b011 && extractBit(encoding, 26) == 0 {
      return decodeLiteralLoad(encoding, at: address)
    }

    // Check for load/store pair
    if extractBits(encoding, 27, 29) == 0b101 {
      return decodeLoadStorePair(encoding, at: address)
    }

    // Check for load/store register (various addressing modes)
    let op0 = extractBits(encoding, 28, 31)
    let op1 = extractBits(encoding, 26, 26)
    let op2 = extractBits(encoding, 23, 24)
    let op3 = extractBits(encoding, 16, 21)
    let op4 = extractBits(encoding, 10, 11)

    // Load/store register (unsigned immediate)
    if op0 == 0b1111 || op0 == 0b1110 || op0 == 0b0111 || op0 == 0b0110 || op0 == 0b1011
      || op0 == 0b1010 || op0 == 0b0011 || op0 == 0b0010
    {
      if extractBit(encoding, 24) == 1 {
        return decodeLoadStoreUnsignedImmediate(encoding, at: address)
      }
    }

    // Load/store register (register offset)
    if op4 == 0b10 && extractBit(encoding, 21) == 1 {
      return decodeLoadStoreRegisterOffset(encoding, at: address)
    }

    // Load/store register (unscaled immediate, pre/post-index)
    if extractBit(encoding, 24) == 0 && extractBit(encoding, 21) == 0 {
      return decodeLoadStoreUnscaledPrePost(encoding, at: address)
    }

    return makeUnknown(encoding, at: address)
  }

  // MARK: - Literal Load

  private func decodeLiteralLoad(_ encoding: UInt32, at address: UInt64) -> Instruction {
    let opc = extractBits(encoding, 30, 31)
    let v = extractBit(encoding, 26)
    let imm19 = extractBits(encoding, 5, 23)
    let rt = extractBits(encoding, 0, 4)

    let target = computeBranchTarget(imm19, bits: 19, scale: 4, pc: address)

    // Determine size and mnemonic
    let mnemonic: String
    let reg: Register

    if v == 0 {
      // General purpose register
      switch opc {
      case 0b00:
        mnemonic = "ldr"
        reg = gprRegister(rt, is64bit: false)
      case 0b01:
        mnemonic = "ldr"
        reg = gprRegister(rt, is64bit: true)
      case 0b10:
        mnemonic = "ldrsw"
        reg = gprRegister(rt, is64bit: true)
      case 0b11:
        mnemonic = "prfm"
        reg = .general(Int(rt), .x)  // Prefetch hint
      default:
        return makeUnknown(encoding, at: address)
      }
    } else {
      // SIMD/FP register
      let size: RegisterWidth
      switch opc {
      case 0b00: size = .s
      case 0b01: size = .d
      case 0b10: size = .q
      default: return makeUnknown(encoding, at: address)
      }
      mnemonic = "ldr"
      reg = .simd(Int(rt), size)
    }

    return Instruction(
      address: address,
      encoding: encoding,
      mnemonic: mnemonic,
      operands: [.register(reg), .address(target)],
      category: .loadStore,
      targetAddress: target
    )
  }

  // MARK: - Load/Store Pair

  private func decodeLoadStorePair(_ encoding: UInt32, at address: UInt64) -> Instruction {
    let opc = extractBits(encoding, 30, 31)
    let v = extractBit(encoding, 26)
    let mode = extractBits(encoding, 23, 24)  // 01=post, 11=pre, 10=signed offset
    let l = extractBit(encoding, 22)  // 0=store, 1=load
    let imm7 = extractBits(encoding, 15, 21)
    let rt2 = extractBits(encoding, 10, 14)
    let rn = extractBits(encoding, 5, 9)
    let rt = extractBits(encoding, 0, 4)

    // Determine register size
    let is64bit: Bool
    let scale: Int

    if v == 0 {
      // General purpose
      switch opc {
      case 0b00:
        is64bit = false
        scale = 4
      case 0b01:
        is64bit = false
        scale = 4  // STGP/LDPSW in this encoding space
      case 0b10:
        is64bit = true
        scale = 8
      case 0b11:
        is64bit = true
        scale = 8
      default: return makeUnknown(encoding, at: address)
      }
    } else {
      // SIMD/FP - not fully implemented
      is64bit = opc >= 2
      scale = is64bit ? 8 : 4
    }

    // Sign-extend and scale the immediate
    let offset = signExtend(imm7, bits: 7) * Int64(scale)

    let regT1 = gprRegister(rt, is64bit: is64bit)
    let regT2 = gprRegister(rt2, is64bit: is64bit)
    let regN = gprRegister(rn, is64bit: true, allowSP: true)

    let mnemonic: String
    if l == 0 {
      mnemonic = "stp"
    } else {
      mnemonic = opc == 0b01 && v == 0 ? "ldpsw" : "ldp"
    }

    // Determine index mode
    let indexMode: MemoryIndexMode
    switch mode {
    case 0b01: indexMode = .postIndex
    case 0b11: indexMode = .preIndex
    case 0b10: indexMode = .offset
    default: return makeUnknown(encoding, at: address)
    }

    return Instruction(
      address: address,
      encoding: encoding,
      mnemonic: mnemonic,
      operands: [
        .register(regT1),
        .register(regT2),
        .memory(base: regN, offset: offset, indexMode: indexMode),
      ],
      category: .loadStore
    )
  }

  // MARK: - Load/Store Unsigned Immediate

  private func decodeLoadStoreUnsignedImmediate(_ encoding: UInt32, at address: UInt64)
    -> Instruction
  {
    let size = extractBits(encoding, 30, 31)
    let v = extractBit(encoding, 26)
    let opc = extractBits(encoding, 22, 23)
    let imm12 = extractBits(encoding, 10, 21)
    let rn = extractBits(encoding, 5, 9)
    let rt = extractBits(encoding, 0, 4)

    let regN = gprRegister(rn, is64bit: true, allowSP: true)

    // Determine mnemonic and register based on size, v, opc
    let mnemonic: String
    let reg: Register
    let scale: Int

    if v == 0 {
      // General purpose register
      switch (size, opc) {
      // Byte
      case (0b00, 0b00):
        mnemonic = "strb"
        reg = gprRegister(rt, is64bit: false)
        scale = 1
      case (0b00, 0b01):
        mnemonic = "ldrb"
        reg = gprRegister(rt, is64bit: false)
        scale = 1
      case (0b00, 0b10):
        mnemonic = "ldrsb"
        reg = gprRegister(rt, is64bit: true)
        scale = 1
      case (0b00, 0b11):
        mnemonic = "ldrsb"
        reg = gprRegister(rt, is64bit: false)
        scale = 1
      // Halfword
      case (0b01, 0b00):
        mnemonic = "strh"
        reg = gprRegister(rt, is64bit: false)
        scale = 2
      case (0b01, 0b01):
        mnemonic = "ldrh"
        reg = gprRegister(rt, is64bit: false)
        scale = 2
      case (0b01, 0b10):
        mnemonic = "ldrsh"
        reg = gprRegister(rt, is64bit: true)
        scale = 2
      case (0b01, 0b11):
        mnemonic = "ldrsh"
        reg = gprRegister(rt, is64bit: false)
        scale = 2
      // Word
      case (0b10, 0b00):
        mnemonic = "str"
        reg = gprRegister(rt, is64bit: false)
        scale = 4
      case (0b10, 0b01):
        mnemonic = "ldr"
        reg = gprRegister(rt, is64bit: false)
        scale = 4
      case (0b10, 0b10):
        mnemonic = "ldrsw"
        reg = gprRegister(rt, is64bit: true)
        scale = 4
      // Doubleword
      case (0b11, 0b00):
        mnemonic = "str"
        reg = gprRegister(rt, is64bit: true)
        scale = 8
      case (0b11, 0b01):
        mnemonic = "ldr"
        reg = gprRegister(rt, is64bit: true)
        scale = 8
      // Prefetch
      case (0b11, 0b10):
        mnemonic = "prfm"
        reg = .general(Int(rt), .x)
        scale = 8
      default: return makeUnknown(encoding, at: address)
      }
    } else {
      // SIMD/FP register
      let width: RegisterWidth
      switch size {
      case 0b00:
        width = opc == 0 ? .b : .b
        scale = 1
      case 0b01:
        width = .h
        scale = 2
      case 0b10:
        width = .s
        scale = 4
      case 0b11:
        width = .d
        scale = 8
      default: return makeUnknown(encoding, at: address)
      }

      if opc >= 2 && size == 0 {
        // Q register
        mnemonic = opc == 2 ? "str" : "ldr"
        reg = .simd(Int(rt), .q)
        return Instruction(
          address: address,
          encoding: encoding,
          mnemonic: mnemonic,
          operands: [
            .register(reg),
            .memory(base: regN, offset: Int64(imm12) * 16, indexMode: .offset),
          ],
          category: .loadStore
        )
      }

      mnemonic = opc == 0 ? "str" : "ldr"
      reg = .simd(Int(rt), width)
    }

    let offset = Int64(imm12) * Int64(scale)

    return Instruction(
      address: address,
      encoding: encoding,
      mnemonic: mnemonic,
      operands: [.register(reg), .memory(base: regN, offset: offset, indexMode: .offset)],
      category: .loadStore
    )
  }

  // MARK: - Load/Store Register Offset

  private func decodeLoadStoreRegisterOffset(_ encoding: UInt32, at address: UInt64) -> Instruction
  {
    let size = extractBits(encoding, 30, 31)
    let v = extractBit(encoding, 26)
    let opc = extractBits(encoding, 22, 23)
    let rm = extractBits(encoding, 16, 20)
    let option = extractBits(encoding, 13, 15)
    let s = extractBit(encoding, 12)
    let rn = extractBits(encoding, 5, 9)
    let rt = extractBits(encoding, 0, 4)

    let regN = gprRegister(rn, is64bit: true, allowSP: true)

    // Determine extend type
    let extendType: ExtendType?
    let rmIs64bit: Bool
    switch option {
    case 0b010:
      extendType = .uxtw
      rmIs64bit = false
    case 0b011:
      extendType = nil
      rmIs64bit = true  // LSL or no extend
    case 0b110:
      extendType = .sxtw
      rmIs64bit = false
    case 0b111:
      extendType = .sxtx
      rmIs64bit = true
    default: return makeUnknown(encoding, at: address)
    }

    let regM = gprRegister(rm, is64bit: rmIs64bit)

    // Determine mnemonic based on size and opc
    let mnemonic: String
    let reg: Register

    if v == 0 {
      switch (size, opc) {
      case (0b00, 0b00):
        mnemonic = "strb"
        reg = gprRegister(rt, is64bit: false)
      case (0b00, 0b01):
        mnemonic = "ldrb"
        reg = gprRegister(rt, is64bit: false)
      case (0b00, 0b10):
        mnemonic = "ldrsb"
        reg = gprRegister(rt, is64bit: true)
      case (0b00, 0b11):
        mnemonic = "ldrsb"
        reg = gprRegister(rt, is64bit: false)
      case (0b01, 0b00):
        mnemonic = "strh"
        reg = gprRegister(rt, is64bit: false)
      case (0b01, 0b01):
        mnemonic = "ldrh"
        reg = gprRegister(rt, is64bit: false)
      case (0b01, 0b10):
        mnemonic = "ldrsh"
        reg = gprRegister(rt, is64bit: true)
      case (0b01, 0b11):
        mnemonic = "ldrsh"
        reg = gprRegister(rt, is64bit: false)
      case (0b10, 0b00):
        mnemonic = "str"
        reg = gprRegister(rt, is64bit: false)
      case (0b10, 0b01):
        mnemonic = "ldr"
        reg = gprRegister(rt, is64bit: false)
      case (0b10, 0b10):
        mnemonic = "ldrsw"
        reg = gprRegister(rt, is64bit: true)
      case (0b11, 0b00):
        mnemonic = "str"
        reg = gprRegister(rt, is64bit: true)
      case (0b11, 0b01):
        mnemonic = "ldr"
        reg = gprRegister(rt, is64bit: true)
      case (0b11, 0b10):
        mnemonic = "prfm"
        reg = .general(Int(rt), .x)
      default: return makeUnknown(encoding, at: address)
      }
    } else {
      mnemonic = opc == 0 ? "str" : "ldr"
      let width: RegisterWidth
      switch size {
      case 0b00: width = .b
      case 0b01: width = .h
      case 0b10: width = .s
      case 0b11: width = .d
      default: return makeUnknown(encoding, at: address)
      }
      reg = .simd(Int(rt), width)
    }

    let shift = s == 1 ? Int(size) : nil

    return Instruction(
      address: address,
      encoding: encoding,
      mnemonic: mnemonic,
      operands: [
        .register(reg),
        .memoryRegister(base: regN, index: regM, extend: extendType, shift: shift),
      ],
      category: .loadStore
    )
  }

  // MARK: - Load/Store Unscaled/Pre/Post-Index

  private func decodeLoadStoreUnscaledPrePost(_ encoding: UInt32, at address: UInt64) -> Instruction
  {
    let size = extractBits(encoding, 30, 31)
    let v = extractBit(encoding, 26)
    let opc = extractBits(encoding, 22, 23)
    let imm9 = extractBits(encoding, 12, 20)
    let mode = extractBits(encoding, 10, 11)
    let rn = extractBits(encoding, 5, 9)
    let rt = extractBits(encoding, 0, 4)

    let offset = signExtend(imm9, bits: 9)
    let regN = gprRegister(rn, is64bit: true, allowSP: true)

    // Determine index mode
    let indexMode: MemoryIndexMode
    switch mode {
    case 0b00: indexMode = .offset  // Unscaled
    case 0b01: indexMode = .postIndex
    case 0b11: indexMode = .preIndex
    default: return makeUnknown(encoding, at: address)
    }

    // Determine mnemonic
    let baseMnemonic: String
    let reg: Register

    if v == 0 {
      switch (size, opc) {
      case (0b00, 0b00):
        baseMnemonic = mode == 0 ? "sturb" : "strb"
        reg = gprRegister(rt, is64bit: false)
      case (0b00, 0b01):
        baseMnemonic = mode == 0 ? "ldurb" : "ldrb"
        reg = gprRegister(rt, is64bit: false)
      case (0b00, 0b10):
        baseMnemonic = mode == 0 ? "ldursb" : "ldrsb"
        reg = gprRegister(rt, is64bit: true)
      case (0b00, 0b11):
        baseMnemonic = mode == 0 ? "ldursb" : "ldrsb"
        reg = gprRegister(rt, is64bit: false)
      case (0b01, 0b00):
        baseMnemonic = mode == 0 ? "sturh" : "strh"
        reg = gprRegister(rt, is64bit: false)
      case (0b01, 0b01):
        baseMnemonic = mode == 0 ? "ldurh" : "ldrh"
        reg = gprRegister(rt, is64bit: false)
      case (0b01, 0b10):
        baseMnemonic = mode == 0 ? "ldursh" : "ldrsh"
        reg = gprRegister(rt, is64bit: true)
      case (0b01, 0b11):
        baseMnemonic = mode == 0 ? "ldursh" : "ldrsh"
        reg = gprRegister(rt, is64bit: false)
      case (0b10, 0b00):
        baseMnemonic = mode == 0 ? "stur" : "str"
        reg = gprRegister(rt, is64bit: false)
      case (0b10, 0b01):
        baseMnemonic = mode == 0 ? "ldur" : "ldr"
        reg = gprRegister(rt, is64bit: false)
      case (0b10, 0b10):
        baseMnemonic = mode == 0 ? "ldursw" : "ldrsw"
        reg = gprRegister(rt, is64bit: true)
      case (0b11, 0b00):
        baseMnemonic = mode == 0 ? "stur" : "str"
        reg = gprRegister(rt, is64bit: true)
      case (0b11, 0b01):
        baseMnemonic = mode == 0 ? "ldur" : "ldr"
        reg = gprRegister(rt, is64bit: true)
      default: return makeUnknown(encoding, at: address)
      }
    } else {
      baseMnemonic = opc == 0 ? (mode == 0 ? "stur" : "str") : (mode == 0 ? "ldur" : "ldr")
      let width: RegisterWidth
      switch size {
      case 0b00: width = .b
      case 0b01: width = .h
      case 0b10: width = .s
      case 0b11: width = .d
      default: return makeUnknown(encoding, at: address)
      }
      reg = .simd(Int(rt), width)
    }

    return Instruction(
      address: address,
      encoding: encoding,
      mnemonic: baseMnemonic,
      operands: [.register(reg), .memory(base: regN, offset: offset, indexMode: indexMode)],
      category: .loadStore
    )
  }

  // MARK: - Unknown

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
