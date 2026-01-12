// Branch.swift
// Disassembler
//
// Branch instruction decoder (B, BL, BR, RET, CBZ, CBNZ, TBZ, TBNZ)

import Foundation

/// Branch instruction decoder
public struct BranchDecoder: Sendable {

  public init() {}

  /// Main decode entry point
  public func decode(_ encoding: UInt32, at address: UInt64) -> Instruction {
    // Check bit 26 for immediate vs register
    if extractBit(encoding, 26) == 1 {
      return decodeUnconditionalImmediate(encoding, at: address)
    }

    // Check for conditional branch (B.cond)
    if extractBits(encoding, 25, 31) == 0b0101010 {
      return decodeConditional(encoding, at: address)
    }

    // Check for compare and branch (CBZ/CBNZ)
    let op0 = extractBits(encoding, 25, 30)
    if op0 == 0b011010 {
      return decodeCompareAndBranch(encoding, at: address)
    }

    // Check for test and branch (TBZ/TBNZ)
    if op0 == 0b011011 {
      return decodeTestAndBranch(encoding, at: address)
    }

    // Unconditional register branch
    return decodeUnconditionalRegister(encoding, at: address)
  }

  // MARK: - Unconditional Immediate

  /// Decode B and BL instructions
  public func decodeUnconditionalImmediate(_ encoding: UInt32, at address: UInt64) -> Instruction {
    // B: 0b000101 (bit 31 = 0)
    // BL: 0b100101 (bit 31 = 1)
    let isLink = extractBit(encoding, 31) == 1
    let mnemonic = isLink ? "bl" : "b"

    // imm26 is bits [25:0]
    let imm26 = extractBits(encoding, 0, 25)
    let target = computeBranchTarget(imm26, bits: 26, scale: 4, pc: address)

    return Instruction(
      address: address,
      encoding: encoding,
      mnemonic: mnemonic,
      operands: [.address(target)],
      category: .branch,
      targetAddress: target
    )
  }

  // MARK: - Conditional Branch

  /// Decode B.cond instructions
  public func decodeConditional(_ encoding: UInt32, at address: UInt64) -> Instruction {
    // Format: 01010100 imm19 0 cond
    let cond = extractBits(encoding, 0, 3)
    let imm19 = extractBits(encoding, 5, 23)
    let target = computeBranchTarget(imm19, bits: 19, scale: 4, pc: address)

    guard let condCode = ConditionCode(code: Int(cond)) else {
      return makeUnknown(encoding, at: address)
    }

    let mnemonic = "b.\(condCode.rawValue)"

    return Instruction(
      address: address,
      encoding: encoding,
      mnemonic: mnemonic,
      operands: [.address(target)],
      category: .branch,
      targetAddress: target
    )
  }

  // MARK: - Compare and Branch

  /// Decode CBZ and CBNZ instructions
  public func decodeCompareAndBranch(_ encoding: UInt32, at address: UInt64) -> Instruction {
    // CBZ:  sf 0110100 imm19 Rt
    // CBNZ: sf 0110101 imm19 Rt
    let sf = extractBit(encoding, 31)  // 0=32bit, 1=64bit
    let op = extractBit(encoding, 24)  // 0=CBZ, 1=CBNZ
    let imm19 = extractBits(encoding, 5, 23)
    let rt = extractBits(encoding, 0, 4)

    let mnemonic = op == 0 ? "cbz" : "cbnz"
    let target = computeBranchTarget(imm19, bits: 19, scale: 4, pc: address)
    let reg = gprRegister(rt, is64bit: sf == 1)

    return Instruction(
      address: address,
      encoding: encoding,
      mnemonic: mnemonic,
      operands: [.register(reg), .address(target)],
      category: .branch,
      targetAddress: target
    )
  }

  // MARK: - Test and Branch

  /// Decode TBZ and TBNZ instructions
  public func decodeTestAndBranch(_ encoding: UInt32, at address: UInt64) -> Instruction {
    // TBZ:  b5 0110110 b40 imm14 Rt
    // TBNZ: b5 0110111 b40 imm14 Rt
    let b5 = extractBit(encoding, 31)
    let op = extractBit(encoding, 24)  // 0=TBZ, 1=TBNZ
    let b40 = extractBits(encoding, 19, 23)
    let imm14 = extractBits(encoding, 5, 18)
    let rt = extractBits(encoding, 0, 4)

    let bitNum = (b5 << 5) | b40
    let mnemonic = op == 0 ? "tbz" : "tbnz"
    let target = computeBranchTarget(imm14, bits: 14, scale: 4, pc: address)

    // TBZ/TBNZ always uses X register if testing bit 32+
    let is64bit = b5 == 1
    let reg = gprRegister(rt, is64bit: is64bit)

    return Instruction(
      address: address,
      encoding: encoding,
      mnemonic: mnemonic,
      operands: [
        .register(reg),
        .immediate(Int64(bitNum)),
        .address(target),
      ],
      category: .branch,
      targetAddress: target
    )
  }

  // MARK: - Unconditional Register

  /// Decode BR, BLR, RET, ERET, DRPS and PAC variants
  public func decodeUnconditionalRegister(_ encoding: UInt32, at address: UInt64) -> Instruction {
    // Format: 1101011 opc op2 op3 Rn op4
    let opc = extractBits(encoding, 21, 24)
    let op2 = extractBits(encoding, 16, 20)
    let op3 = extractBits(encoding, 10, 15)
    let rn = extractBits(encoding, 5, 9)
    let op4 = extractBits(encoding, 0, 4)

    // Check for PAC variants first
    if let pacInst = decodePACBranch(
      encoding, at: address, opc: opc, op2: op2, op3: op3, rn: rn, op4: op4)
    {
      return pacInst
    }

    // Standard unconditional register branches
    switch (opc, op2, op3, op4) {
    // BR Xn
    case (0b0000, 0b11111, 0b000000, 0b00000):
      let reg = gprRegister(rn, is64bit: true)
      return Instruction(
        address: address,
        encoding: encoding,
        mnemonic: "br",
        operands: [.register(reg)],
        category: .branch
      )

    // BLR Xn
    case (0b0001, 0b11111, 0b000000, 0b00000):
      let reg = gprRegister(rn, is64bit: true)
      return Instruction(
        address: address,
        encoding: encoding,
        mnemonic: "blr",
        operands: [.register(reg)],
        category: .branch
      )

    // RET {Xn}
    case (0b0010, 0b11111, 0b000000, 0b00000):
      if rn == 30 {
        // RET with default x30
        return Instruction(
          address: address,
          encoding: encoding,
          mnemonic: "ret",
          operands: [],
          category: .branch
        )
      } else {
        let reg = gprRegister(rn, is64bit: true)
        return Instruction(
          address: address,
          encoding: encoding,
          mnemonic: "ret",
          operands: [.register(reg)],
          category: .branch
        )
      }

    // ERET
    case (0b0100, 0b11111, 0b000000, 0b00000) where rn == 0b11111:
      return Instruction(
        address: address,
        encoding: encoding,
        mnemonic: "eret",
        operands: [],
        category: .system
      )

    // DRPS
    case (0b0101, 0b11111, 0b000000, 0b00000) where rn == 0b11111:
      return Instruction(
        address: address,
        encoding: encoding,
        mnemonic: "drps",
        operands: [],
        category: .system
      )

    default:
      return makeUnknown(encoding, at: address)
    }
  }

  // MARK: - PAC Branch Instructions

  private func decodePACBranch(
    _ encoding: UInt32,
    at address: UInt64,
    opc: UInt32,
    op2: UInt32,
    op3: UInt32,
    rn: UInt32,
    op4: UInt32
  ) -> Instruction? {
    // BRAA, BRAB, BLRAA, BLRAB
    let rm = op4

    switch (opc, op2, op3) {
    // BRAAZ Xn
    case (0b0000, 0b11111, 0b000010) where rm == 0b11111:
      return makePACBranch("braaz", encoding, address, rn: rn)

    // BRABZ Xn
    case (0b0000, 0b11111, 0b000011) where rm == 0b11111:
      return makePACBranch("brabz", encoding, address, rn: rn)

    // BLRAAZ Xn
    case (0b0001, 0b11111, 0b000010) where rm == 0b11111:
      return makePACBranch("blraaz", encoding, address, rn: rn)

    // BLRABZ Xn
    case (0b0001, 0b11111, 0b000011) where rm == 0b11111:
      return makePACBranch("blrabz", encoding, address, rn: rn)

    // RETAA
    case (0b0010, 0b11111, 0b000010) where rn == 0b11111 && rm == 0b11111:
      return Instruction(
        address: address,
        encoding: encoding,
        mnemonic: "retaa",
        operands: [],
        category: .pac,
        annotation: "[PAC] Authenticated return (A key)"
      )

    // RETAB
    case (0b0010, 0b11111, 0b000011) where rn == 0b11111 && rm == 0b11111:
      return Instruction(
        address: address,
        encoding: encoding,
        mnemonic: "retab",
        operands: [],
        category: .pac,
        annotation: "[PAC] Authenticated return (B key)"
      )

    // BRAA Xn, Xm
    case (0b1000, 0b11111, 0b000010):
      return makePACBranchWithModifier("braa", encoding, address, rn: rn, rm: rm)

    // BRAB Xn, Xm
    case (0b1000, 0b11111, 0b000011):
      return makePACBranchWithModifier("brab", encoding, address, rn: rn, rm: rm)

    // BLRAA Xn, Xm
    case (0b1001, 0b11111, 0b000010):
      return makePACBranchWithModifier("blraa", encoding, address, rn: rn, rm: rm)

    // BLRAB Xn, Xm
    case (0b1001, 0b11111, 0b000011):
      return makePACBranchWithModifier("blrab", encoding, address, rn: rn, rm: rm)

    default:
      return nil
    }
  }

  private func makePACBranch(_ mnemonic: String, _ encoding: UInt32, _ address: UInt64, rn: UInt32)
    -> Instruction
  {
    let reg = gprRegister(rn, is64bit: true)
    return Instruction(
      address: address,
      encoding: encoding,
      mnemonic: mnemonic,
      operands: [.register(reg)],
      category: .pac,
      annotation: "[PAC] Authenticated branch"
    )
  }

  private func makePACBranchWithModifier(
    _ mnemonic: String, _ encoding: UInt32, _ address: UInt64, rn: UInt32, rm: UInt32
  ) -> Instruction {
    let regN = gprRegister(rn, is64bit: true)
    let regM = gprRegister(rm, is64bit: true, allowSP: true)
    return Instruction(
      address: address,
      encoding: encoding,
      mnemonic: mnemonic,
      operands: [.register(regN), .register(regM)],
      category: .pac,
      annotation: "[PAC] Authenticated branch"
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
