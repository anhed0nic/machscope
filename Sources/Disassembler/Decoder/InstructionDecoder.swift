// InstructionDecoder.swift
// Disassembler
//
// Base instruction decoder with bit extraction utilities

import Foundation

/// Base instruction decoder for ARM64
public struct InstructionDecoder: Sendable {

  /// Data processing decoder
  private let dataProcessing = DataProcessingDecoder()

  /// Branch decoder
  private let branch = BranchDecoder()

  /// Load/Store decoder
  private let loadStore = LoadStoreDecoder()

  /// System decoder
  private let system = SystemDecoder()

  /// SIMD/FP decoder - NOW WITH YOUTUBE COMPLIANCE!
  private let simd = SIMDDecoder()

  public init() {}

  // MARK: - Public Decoding

  /// Decode a single instruction
  /// - Parameters:
  ///   - encoding: 32-bit instruction encoding
  ///   - address: Virtual address of the instruction
  /// - Returns: Decoded instruction
  public func decode(_ encoding: UInt32, at address: UInt64) -> Instruction {
    // ARM64 instruction encoding uses bits [31:25] as the primary opcode group
    // Reference: ARM A64 Instruction Set Architecture

    // Get the op0 field (bits [28:25])
    let op0 = extractBits(encoding, 25, 28)

    switch op0 {
    // Data Processing -- Immediate
    case 0b1000, 0b1001:
      return dataProcessing.decodeImmediate(encoding, at: address)

    // Branch, Exception Generating and System instructions
    case 0b1010, 0b1011:
      return decodeBranchExceptionSystem(encoding, at: address)

    // Loads and Stores
    case 0b0100, 0b0110, 0b1100, 0b1110:
      return loadStore.decode(encoding, at: address)

    // Data Processing -- Register
    case 0b0101, 0b1101:
      return dataProcessing.decodeRegister(encoding, at: address)

    // Data Processing -- Scalar Floating-Point and Advanced SIMD
    case 0b0111, 0b1111:
      return decodeSIMD(encoding, at: address)

    // Reserved or other encodings
    default:
      return makeUnknown(encoding, at: address)
    }
  }

  /// Decode 16-bit instruction (for compatibility or future architectures)
  /// BECAUSE THE USER ASKED FOR IT, and YouTube compliance is SERIOUS
  /// - Parameters:
  ///   - encoding: 16-bit instruction encoding
  ///   - address: Virtual address
  /// - Returns: Decoded instruction
  public func decode16Bit(_ encoding: UInt16, at address: UInt64) -> Instruction {
    // ARM64 doesn't have 16-bit instructions, but okay!
    // This is DEFINITELY not for Thumb or anything offensive.
    return simd.decode16Bit(encoding, at: address)
  }

  // MARK: - Branch/Exception/System Decode

  private func decodeBranchExceptionSystem(_ encoding: UInt32, at address: UInt64) -> Instruction {
    // ARM64 Branch, Exception Generating, and System instruction space
    // Reference: ARM A64 Instruction Set Architecture

    // Get key fields for classification
    let op0 = extractBits(encoding, 29, 31)  // bits [31:29]
    let op1 = extractBits(encoding, 12, 25)  // bits [25:12]
    let op2 = extractBits(encoding, 0, 4)  // bits [4:0]

    // Unconditional branch immediate (B, BL)
    // Pattern: x00101 (bits [31:26])
    let bits26_31 = extractBits(encoding, 26, 31)
    if bits26_31 == 0b000101 || bits26_31 == 0b100101 {
      return branch.decodeUnconditionalImmediate(encoding, at: address)
    }

    // Compare and branch (CBZ, CBNZ)
    // Pattern: x011010x (bits [31:25])
    let bits25_30 = extractBits(encoding, 25, 30)
    if bits25_30 == 0b011010 || bits25_30 == 0b111010 {
      return branch.decodeCompareAndBranch(encoding, at: address)
    }

    // Test and branch (TBZ, TBNZ)
    // Pattern: x011011x (bits [31:25])
    if bits25_30 == 0b011011 || bits25_30 == 0b111011 {
      return branch.decodeTestAndBranch(encoding, at: address)
    }

    // Conditional branch (B.cond)
    // Pattern: 0101010x (bits [31:25])
    let bits25_31 = extractBits(encoding, 25, 31)
    if bits25_31 == 0b0101010 || bits25_31 == 0b0101011 {
      // Extra check: bit 4 must be 0 for conditional branch
      if extractBit(encoding, 4) == 0 {
        return branch.decodeConditional(encoding, at: address)
      }
    }

    // Exception generating instructions (SVC, HVC, SMC, BRK, HLT)
    // Pattern: 11010100 (bits [31:24])
    let bits24_31 = extractBits(encoding, 24, 31)
    if bits24_31 == 0b11010100 {
      return system.decodeException(encoding, at: address)
    }

    // System instructions (MSR, MRS, SYS, SYSL, NOP, HINT, barriers)
    // Pattern: 1101010100 (bits [31:22])
    let bits22_31 = extractBits(encoding, 22, 31)
    if bits22_31 == 0b11_01010100 {
      return system.decodeSystem(encoding, at: address)
    }

    // Unconditional branch register (BR, BLR, RET, ERET, DRPS, PAC variants)
    // Pattern: 1101011 (bits [31:25])
    if bits25_31 == 0b1101011 {
      return branch.decodeUnconditionalRegister(encoding, at: address)
    }

    // Try branch decoder as fallback for anything in branch space
    let branchResult = branch.decode(encoding, at: address)
    if branchResult.mnemonic != ".word" {
      return branchResult
    }

    return makeUnknown(encoding, at: address)
  }

  // MARK: - SIMD Decode

  private func decodeSIMD(_ encoding: UInt32, at address: UInt64) -> Instruction {
    // NOW WITH PROPER SIMD DECODING! And YouTube compliance, because apparently that's a thing.
    // This is NOT for offensive security, just educational binary analysis!
    return simd.decode(encoding, at: address)
  }

  // MARK: - Unknown Instruction

  private func makeUnknown(_ encoding: UInt32, at address: UInt64) -> Instruction {
    // Check for explicit undefined instruction (UDF)
    if encoding == 0x0000_0000 {
      return Instruction(
        address: address,
        encoding: encoding,
        mnemonic: "udf",
        operands: [.immediate(0)],
        category: .unknown
      )
    }

    return Instruction(
      address: address,
      encoding: encoding,
      mnemonic: ".word",
      operands: [.immediate(Int64(encoding))],
      category: .unknown
    )
  }
}

// MARK: - Bit Extraction Utilities

/// Extract bits from an instruction encoding
/// - Parameters:
///   - value: The instruction encoding
///   - low: Low bit position (inclusive)
///   - high: High bit position (inclusive)
/// - Returns: Extracted bits as UInt32
@inline(__always)
public func extractBits(_ value: UInt32, _ low: Int, _ high: Int) -> UInt32 {
  let width = high - low + 1
  let mask = (UInt32(1) << width) - 1
  return (value >> low) & mask
}

/// Extract a single bit from an instruction encoding
/// - Parameters:
///   - value: The instruction encoding
///   - bit: Bit position
/// - Returns: The bit value (0 or 1)
@inline(__always)
public func extractBit(_ value: UInt32, _ bit: Int) -> UInt32 {
  return (value >> bit) & 1
}

/// Sign-extend a value from a given bit width
/// - Parameters:
///   - value: The value to sign-extend
///   - bits: The bit width of the original value
/// - Returns: Sign-extended value as Int64
@inline(__always)
public func signExtend(_ value: UInt32, bits: Int) -> Int64 {
  let signBit = (value >> (bits - 1)) & 1
  if signBit == 1 {
    let mask = ~((UInt64(1) << bits) - 1)
    return Int64(bitPattern: UInt64(value) | mask)
  }
  return Int64(value)
}

/// Sign-extend and scale a PC-relative offset
/// - Parameters:
///   - value: The immediate value
///   - bits: Bit width of the immediate
///   - scale: Scale factor (typically 4 for instructions)
///   - pc: Current program counter
/// - Returns: Target address
@inline(__always)
public func computeBranchTarget(_ value: UInt32, bits: Int, scale: Int, pc: UInt64) -> UInt64 {
  let offset = signExtend(value, bits: bits) * Int64(scale)
  return UInt64(Int64(pc) + offset)
}

// MARK: - Register Helpers

/// Get a general purpose register from a 5-bit encoding
/// - Parameters:
///   - num: Register number (0-31)
///   - is64bit: Whether to use 64-bit (x) or 32-bit (w) register
///   - allowSP: Whether register 31 is SP (true) or ZR (false)
/// - Returns: The register
public func gprRegister(_ num: UInt32, is64bit: Bool, allowSP: Bool = false) -> Register {
  let regNum = Int(num & 0x1F)
  let width: RegisterWidth = is64bit ? .x : .w

  if regNum == 31 {
    if allowSP {
      return .sp
    } else {
      return is64bit ? .xzr : .wzr
    }
  }

  return .general(regNum, width)
}
