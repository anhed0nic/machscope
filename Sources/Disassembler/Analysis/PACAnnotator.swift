// PACAnnotator.swift
// Disassembler
//
// Pointer Authentication Code instruction annotation

import Foundation

/// PAC instruction category
public enum PACCategory: Sendable {
  case sign  // PACIA, PACIB, PACDA, PACDB
  case authenticate  // AUTIA, AUTIB, AUTDA, AUTDB
  case authenticatedBranch  // BRAA, BRAB, BLRAA, BLRAB
  case authenticatedReturn  // RETAA, RETAB
  case strip  // XPAC instructions
  case none  // Not a PAC instruction
}

/// PAC instruction annotator
public struct PACAnnotator: Sendable {

  public init() {}

  // MARK: - PAC Detection

  /// Check if an encoding is a PAC instruction
  public func isPACInstruction(_ encoding: UInt32) -> Bool {
    getCategory(encoding) != .none
  }

  /// Get the PAC category of an instruction
  public func getCategory(_ encoding: UInt32) -> PACCategory {
    // Check for data authentication instructions (PACIA, AUTIA, etc.)
    // These are in the system instruction space
    if isDataPACInstruction(encoding) {
      return getDataPACCategory(encoding)
    }

    // Check for PAC branch instructions
    if isPACBranchInstruction(encoding) {
      return getPACBranchCategory(encoding)
    }

    // Check for PAC hint instructions
    if isPACHintInstruction(encoding) {
      return .sign  // Hint PAC instructions are signing operations
    }

    return .none
  }

  /// Generate annotation for a PAC instruction
  public func annotate(_ encoding: UInt32) -> String? {
    let category = getCategory(encoding)

    switch category {
    case .sign:
      let key = getPACKey(encoding)
      return "[PAC] Sign pointer with \(key) key"

    case .authenticate:
      let key = getPACKey(encoding)
      return "[PAC] Authenticate pointer with \(key) key"

    case .authenticatedBranch:
      let key = getPACKey(encoding)
      return "[PAC] Authenticated branch (\(key) key)"

    case .authenticatedReturn:
      let key = getPACKey(encoding)
      return "[PAC] Authenticated return (\(key) key)"

    case .strip:
      return "[PAC] Strip pointer authentication"

    case .none:
      return nil
    }
  }

  /// Annotate an instruction with PAC information
  public func annotateInstruction(_ instruction: Instruction) -> Instruction {
    guard isPACInstruction(instruction.encoding) else {
      return instruction
    }

    let category = getCategory(instruction.encoding)
    let annotation = annotate(instruction.encoding)

    return
      instruction
      .withCategory(category == .none ? instruction.category : .pac)
      .withAnnotation(annotation)
  }

  // MARK: - Private Helpers

  private func isDataPACInstruction(_ encoding: UInt32) -> Bool {
    // Data PAC instructions: PACIA, PACIB, PACDA, PACDB, AUTIA, AUTIB, AUTDA, AUTDB
    // These have encoding: 1101 0101 0001 xxxx xxxx xxxx xxxx xxxx
    let op0 = (encoding >> 24) & 0xFF

    // Check for data processing register (misc) - PAC space
    if op0 == 0xDA || op0 == 0xDB {
      let op1 = (encoding >> 10) & 0x3F
      // PAC/AUT operations have specific op1 values
      return (op1 >= 0 && op1 <= 0x1F)
    }

    return false
  }

  private func getDataPACCategory(_ encoding: UInt32) -> PACCategory {
    let op1 = (encoding >> 10) & 0x3F

    // Rough categorization based on op1 field
    if op1 < 8 {
      return .sign  // PACIA, PACIB, PACDA, PACDB variants
    } else if op1 < 16 {
      return .authenticate  // AUTIA, AUTIB, AUTDA, AUTDB variants
    } else {
      return .strip  // XPAC variants
    }
  }

  private func isPACBranchInstruction(_ encoding: UInt32) -> Bool {
    // PAC branch instructions have specific encodings
    // BRAA, BRAB: 1101 0111 0001 xxxx xxxx xxxx xx10 xxxx
    // BLRAA, BLRAB: 1101 0111 0011 xxxx xxxx xxxx xx10 xxxx
    // RETAA, RETAB: 1101 0110 0101 1111 0000 10xx xxxx xxxx

    let top8 = (encoding >> 24) & 0xFF

    // Check for BRAA/BRAB/BLRAA/BLRAB
    if top8 == 0xD7 {
      let op = (encoding >> 21) & 0x7
      let bit10_11 = (encoding >> 10) & 0x3
      if bit10_11 == 0x2 && (op == 0x1 || op == 0x3) {
        return true
      }
    }

    // Check for RETAA/RETAB
    if top8 == 0xD6 {
      let bits21_31 = (encoding >> 21) & 0x7FF
      if bits21_31 == 0x2BF {  // Pattern for RETAA/RETAB
        let op3 = (encoding >> 10) & 0x3F
        return op3 == 0x2 || op3 == 0x3
      }
    }

    // Check for authenticated branch patterns
    let op0 = (encoding >> 24) & 0xFF
    let op2 = (encoding >> 10) & 0x3F

    if op0 == 0xD6 || op0 == 0xD7 {
      // These are branch register instructions
      // Check for PAC variants
      let rn = (encoding >> 5) & 0x1F
      let rm = encoding & 0x1F

      // RETAA: d65f0bff, RETAB: d65f0fff
      if encoding == 0xd65f_0bff || encoding == 0xd65f_0fff {
        return true
      }

      // Check for other authenticated branch patterns
      if op2 == 0x2 || op2 == 0x3 {
        return true
      }
    }

    return false
  }

  private func getPACBranchCategory(_ encoding: UInt32) -> PACCategory {
    let top8 = (encoding >> 24) & 0xFF

    // RETAA/RETAB
    if encoding == 0xd65f_0bff || encoding == 0xd65f_0fff {
      return .authenticatedReturn
    }

    if top8 == 0xD6 {
      let bits21_31 = (encoding >> 21) & 0x7FF
      if bits21_31 == 0x2BF {
        return .authenticatedReturn
      }
    }

    // BRAA/BRAB/BLRAA/BLRAB
    return .authenticatedBranch
  }

  private func isPACHintInstruction(_ encoding: UInt32) -> Bool {
    // PAC hint instructions: PACIASP, PACIBSP, AUTIAZ, etc.
    // These are encoded as HINT instructions
    // Pattern: 1101 0101 0000 0011 0010 xxxx xxx1 1111

    let mask: UInt32 = 0xFFFF_F01F
    let pattern: UInt32 = 0xD503_201F

    if (encoding & mask) != pattern {
      return false
    }

    let crm = (encoding >> 8) & 0xF
    let op2 = (encoding >> 5) & 0x7

    // PAC hints have CRm=3 and various op2 values
    if crm == 3 {
      // op2: 0=paciaz, 1=paciasp, 2=pacibz, 3=pacibsp
      // op2: 4=autiaz, 5=autiasp, 6=autibz, 7=autibsp
      return true
    }

    // Also check CRm=1 for PACIA1716, etc.
    if crm == 1 && (op2 == 0 || op2 == 2 || op2 == 4 || op2 == 6) {
      return true
    }

    // XPACLRI: CRm=0, op2=7
    if crm == 0 && op2 == 7 {
      return true
    }

    return false
  }

  private func getPACKey(_ encoding: UInt32) -> String {
    // Determine A vs B key based on encoding
    // Generally, even op codes use A key, odd use B key

    // Check hint instructions
    let mask: UInt32 = 0xFFFF_F01F
    let pattern: UInt32 = 0xD503_201F
    if (encoding & mask) == pattern {
      let op2 = (encoding >> 5) & 0x7
      return (op2 & 2) == 0 ? "A" : "B"
    }

    // Check data PAC instructions
    let op0 = (encoding >> 24) & 0xFF
    if op0 == 0xDA || op0 == 0xDB {
      let op1 = (encoding >> 10) & 0x3F
      return (op1 & 4) == 0 ? "A" : "B"
    }

    // Check branch instructions - RETAA vs RETAB
    if encoding == 0xd65f_0bff {
      return "A"
    }
    if encoding == 0xd65f_0fff {
      return "B"
    }

    // Default to A
    return "A"
  }
}
