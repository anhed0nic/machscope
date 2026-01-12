// InstructionFormatter.swift
// Disassembler
//
// Assembly notation formatter for ARM64 instructions

import Foundation

/// Instruction formatter for assembly notation
public struct InstructionFormatter: Sendable {

  private let operandFormatter = OperandFormatter()

  public init() {}

  // MARK: - Formatting

  /// Format an instruction for display
  /// - Parameters:
  ///   - instruction: The instruction to format
  ///   - showAddress: Whether to include the address
  ///   - showBytes: Whether to include raw bytes
  /// - Returns: Formatted string
  public func format(
    _ instruction: Instruction,
    showAddress: Bool = true,
    showBytes: Bool = false
  ) -> String {
    var parts: [String] = []

    // Address
    if showAddress {
      parts.append(String(format: "0x%llx:", instruction.address))
    }

    // Bytes
    if showBytes {
      let bytes = formatBytes(instruction.encoding)
      parts.append(bytes)
    }

    // Mnemonic and operands
    let mnemonicPart = formatMnemonicAndOperands(instruction)
    parts.append(mnemonicPart)

    // Comment/annotation
    if let comment = formatComment(instruction) {
      parts.append(comment)
    }

    return parts.joined(separator: "  ")
  }

  /// Format multiple instructions
  /// - Parameters:
  ///   - instructions: Array of instructions
  ///   - showAddress: Whether to include addresses
  ///   - showBytes: Whether to include raw bytes
  /// - Returns: Array of formatted strings
  public func format(
    _ instructions: [Instruction],
    showAddress: Bool = true,
    showBytes: Bool = false
  ) -> [String] {
    instructions.map { format($0, showAddress: showAddress, showBytes: showBytes) }
  }

  // MARK: - Private Helpers

  private func formatBytes(_ encoding: UInt32) -> String {
    let b0 = UInt8(encoding & 0xFF)
    let b1 = UInt8((encoding >> 8) & 0xFF)
    let b2 = UInt8((encoding >> 16) & 0xFF)
    let b3 = UInt8((encoding >> 24) & 0xFF)
    return String(format: "%02x %02x %02x %02x", b0, b1, b2, b3)
  }

  private func formatMnemonicAndOperands(_ instruction: Instruction) -> String {
    let mnemonic = instruction.mnemonic.padding(toLength: 8, withPad: " ", startingAt: 0)

    if instruction.operands.isEmpty {
      return mnemonic.trimmingCharacters(in: .whitespaces)
    }

    let operandStrings = instruction.operands.map { operandFormatter.format($0) }
    let operands = operandStrings.joined(separator: ", ")

    return "\(mnemonic)\(operands)"
  }

  private func formatComment(_ instruction: Instruction) -> String? {
    var comments: [String] = []

    // Add target symbol if present
    if let symbol = instruction.targetSymbol {
      comments.append(symbol)
    }

    // Add annotation if present
    if let annotation = instruction.annotation {
      comments.append(annotation)
    }

    if comments.isEmpty {
      return nil
    }

    return "; " + comments.joined(separator: " ")
  }
}

// MARK: - JSON Output

extension InstructionFormatter {
  /// Format an instruction as JSON
  public func formatJSON(_ instruction: Instruction) -> [String: Any] {
    var dict: [String: Any] = [
      "address": String(format: "0x%llx", instruction.address),
      "encoding": String(format: "0x%08x", instruction.encoding),
      "mnemonic": instruction.mnemonic,
      "category": instruction.category.rawValue,
    ]

    if !instruction.operands.isEmpty {
      dict["operands"] = formatOperandsString(instruction)
    }

    if let target = instruction.targetAddress {
      dict["targetAddress"] = String(format: "0x%llx", target)
    }

    if let symbol = instruction.targetSymbol {
      dict["targetSymbol"] = symbol
    }

    return dict
  }

  private func formatOperandsString(_ instruction: Instruction) -> String {
    instruction.operands.map { operandFormatter.format($0) }.joined(separator: ", ")
  }
}
