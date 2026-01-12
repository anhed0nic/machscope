// ARM64Disassembler.swift
// Disassembler
//
// Main entry point for ARM64 instruction decoding

import Foundation
import MachOKit

/// Configuration options for disassembly
public struct DisassemblyOptions: Sendable {
  /// Whether to resolve symbols
  public var resolveSymbols: Bool

  /// Whether to demangle Swift symbols
  public var demangleSwift: Bool

  /// Whether to annotate PAC instructions
  public var annotatePAC: Bool

  /// Whether to show instruction bytes
  public var showBytes: Bool

  /// Whether to show addresses
  public var showAddresses: Bool

  /// Default options
  public static let `default` = DisassemblyOptions(
    resolveSymbols: true,
    demangleSwift: true,
    annotatePAC: true,
    showBytes: false,
    showAddresses: true
  )

  public init(
    resolveSymbols: Bool = true,
    demangleSwift: Bool = true,
    annotatePAC: Bool = true,
    showBytes: Bool = false,
    showAddresses: Bool = true
  ) {
    self.resolveSymbols = resolveSymbols
    self.demangleSwift = demangleSwift
    self.annotatePAC = annotatePAC
    self.showBytes = showBytes
    self.showAddresses = showAddresses
  }
}

/// Result of disassembling a function or region
public struct DisassemblyResult: Sendable {
  /// The disassembled instructions
  public let instructions: [Instruction]

  /// The start address
  public let startAddress: UInt64

  /// The end address (exclusive)
  public let endAddress: UInt64

  /// Function name if known
  public let functionName: String?

  /// Number of instructions
  public var count: Int { instructions.count }

  /// Total bytes disassembled
  public var byteCount: Int { instructions.count * 4 }
}

/// Main entry point for ARM64 disassembly
public struct ARM64Disassembler: Sendable {

  private let decoder: InstructionDecoder
  private let formatter: InstructionFormatter
  private let pacAnnotator: PACAnnotator
  private let swiftDemangler: SwiftDemangler
  private let symbolResolver: any SymbolResolving
  private let options: DisassemblyOptions

  // MARK: - Initialization

  /// Create a disassembler with default options
  public init() {
    self.init(symbolResolver: SymbolResolver(), options: .default)
  }

  /// Create a disassembler with a MachO binary for symbol resolution
  public init(binary: MachOBinary, options: DisassemblyOptions = .default) {
    self.init(symbolResolver: MachOSymbolResolver(binary: binary), options: options)
  }

  /// Create a disassembler with custom symbol resolver
  public init(symbolResolver: any SymbolResolving, options: DisassemblyOptions = .default) {
    self.decoder = InstructionDecoder()
    self.formatter = InstructionFormatter()
    self.pacAnnotator = PACAnnotator()
    self.swiftDemangler = SwiftDemangler()
    self.symbolResolver = symbolResolver
    self.options = options
  }

  // MARK: - Single Instruction

  /// Decode a single instruction
  /// - Parameters:
  ///   - encoding: The 32-bit instruction encoding
  ///   - address: The address of the instruction
  /// - Returns: Decoded instruction
  public func decode(_ encoding: UInt32, at address: UInt64) -> Instruction {
    var instruction = decoder.decode(encoding, at: address)
    instruction = annotateInstruction(instruction)
    return instruction
  }

  /// Format a single instruction for display
  /// - Parameter instruction: The instruction to format
  /// - Returns: Formatted string
  public func format(_ instruction: Instruction) -> String {
    formatter.format(
      instruction,
      showAddress: options.showAddresses,
      showBytes: options.showBytes
    )
  }

  // MARK: - Data Buffer Disassembly

  /// Disassemble a buffer of bytes
  /// - Parameters:
  ///   - data: The data to disassemble
  ///   - baseAddress: The base address of the data
  /// - Returns: Array of decoded instructions
  /// - Throws: DisassemblyError if data is invalid
  public func disassemble(_ data: Data, at baseAddress: UInt64) throws -> [Instruction] {
    guard data.count >= 4 else {
      if data.count == 0 {
        return []
      }
      throw DisassemblyError.insufficientData(expected: 4, actual: data.count)
    }

    // ARM64 instructions are 4 bytes aligned
    guard baseAddress % 4 == 0 else {
      throw DisassemblyError.invalidAlignment(address: baseAddress, required: 4)
    }

    var instructions: [Instruction] = []
    let instructionCount = data.count / 4

    for i in 0..<instructionCount {
      let offset = i * 4
      let address = baseAddress + UInt64(offset)

      // Read little-endian 32-bit encoding
      let encoding = data.withUnsafeBytes { ptr in
        ptr.load(fromByteOffset: offset, as: UInt32.self)
      }

      let instruction = decode(encoding, at: address)
      instructions.append(instruction)
    }

    return instructions
  }

  /// Disassemble and format a buffer of bytes
  /// - Parameters:
  ///   - data: The data to disassemble
  ///   - baseAddress: The base address of the data
  /// - Returns: Array of formatted instruction strings
  /// - Throws: DisassemblyError if data is invalid
  public func disassembleAndFormat(_ data: Data, at baseAddress: UInt64) throws -> [String] {
    let instructions = try disassemble(data, at: baseAddress)
    return instructions.map { format($0) }
  }

  // MARK: - MachO Binary Disassembly

  /// Disassemble a section from a MachO binary
  /// - Parameters:
  ///   - section: The section to disassemble
  ///   - binary: The MachO binary
  /// - Returns: DisassemblyResult containing instructions
  /// - Throws: DisassemblyError if disassembly fails
  public func disassembleSection(_ section: Section, from binary: MachOBinary) throws
    -> DisassemblyResult
  {
    let data: Data
    do {
      data = try binary.readSectionData(section)
    } catch {
      throw DisassemblyError.sectionNotFound(name: section.name)
    }

    let instructions = try disassemble(data, at: section.address)

    return DisassemblyResult(
      instructions: instructions,
      startAddress: section.address,
      endAddress: section.address + UInt64(data.count),
      functionName: nil
    )
  }

  /// Disassemble a function by name
  /// - Parameters:
  ///   - name: The function name (or symbol name)
  ///   - binary: The MachO binary
  /// - Returns: DisassemblyResult containing instructions
  /// - Throws: DisassemblyError if function not found
  public func disassembleFunction(_ name: String, from binary: MachOBinary) throws
    -> DisassemblyResult
  {
    // Find the symbol
    guard let symbol = binary.symbol(named: name) else {
      throw DisassemblyError.symbolNotFound(name: name)
    }

    // Get the __TEXT,__text section
    guard let textSection = binary.section(segment: "__TEXT", section: "__text") else {
      throw DisassemblyError.sectionNotFound(name: "__text")
    }

    let textData: Data
    do {
      textData = try binary.readSectionData(textSection)
    } catch {
      throw DisassemblyError.sectionNotFound(name: "__text")
    }

    // Calculate the offset within the section
    let sectionStart = textSection.address
    let sectionEnd = sectionStart + UInt64(textData.count)

    guard symbol.address >= sectionStart && symbol.address < sectionEnd else {
      throw DisassemblyError.addressOutOfRange(
        address: symbol.address,
        validRange: sectionStart..<sectionEnd
      )
    }

    let startOffset = Int(symbol.address - sectionStart)

    // Find the end of the function (next symbol or section end)
    let endAddress = findFunctionEnd(
      startAddress: symbol.address,
      in: binary,
      sectionEnd: sectionEnd
    )
    let endOffset = Int(endAddress - sectionStart)

    // Extract function data
    let functionData = textData[startOffset..<endOffset]
    let instructions = try disassemble(Data(functionData), at: symbol.address)

    let displayName =
      options.demangleSwift && swiftDemangler.isSwiftSymbol(name)
      ? swiftDemangler.demangle(name)
      : name

    return DisassemblyResult(
      instructions: instructions,
      startAddress: symbol.address,
      endAddress: endAddress,
      functionName: displayName
    )
  }

  /// Disassemble a range of addresses
  /// - Parameters:
  ///   - startAddress: Start address
  ///   - endAddress: End address (exclusive)
  ///   - binary: The MachO binary
  /// - Returns: DisassemblyResult containing instructions
  /// - Throws: DisassemblyError if range is invalid
  public func disassembleRange(
    from startAddress: UInt64,
    to endAddress: UInt64,
    in binary: MachOBinary
  ) throws -> DisassemblyResult {
    guard startAddress < endAddress else {
      throw DisassemblyError.invalidAddressRange(start: startAddress, end: endAddress)
    }

    guard startAddress % 4 == 0 else {
      throw DisassemblyError.invalidAlignment(address: startAddress, required: 4)
    }

    // Find the section containing this address
    guard let (section, sectionData) = findSection(containing: startAddress, in: binary) else {
      throw DisassemblyError.addressOutOfRange(
        address: startAddress,
        validRange: 0..<0
      )
    }

    let sectionStart = section.address
    let sectionEnd = sectionStart + UInt64(sectionData.count)

    // Clamp end address to section end if it extends beyond
    let clampedEndAddress = min(endAddress, sectionEnd)

    let startOffset = Int(startAddress - sectionStart)
    let endOffset = Int(clampedEndAddress - sectionStart)

    guard startOffset >= 0 && startOffset < sectionData.count else {
      throw DisassemblyError.addressOutOfRange(
        address: startAddress,
        validRange: sectionStart..<sectionEnd
      )
    }

    guard endOffset > startOffset && endOffset <= sectionData.count else {
      throw DisassemblyError.addressOutOfRange(
        address: clampedEndAddress,
        validRange: sectionStart..<sectionEnd
      )
    }

    let rangeData = sectionData.subdata(in: startOffset..<endOffset)
    let instructions = try disassemble(rangeData, at: startAddress)

    return DisassemblyResult(
      instructions: instructions,
      startAddress: startAddress,
      endAddress: clampedEndAddress,
      functionName: symbolResolver.symbol(at: startAddress)
    )
  }

  // MARK: - Private Helpers

  /// Annotate an instruction with symbols, PAC info, etc.
  private func annotateInstruction(_ instruction: Instruction) -> Instruction {
    var result = instruction

    // Resolve target symbol
    if options.resolveSymbols, let targetAddr = instruction.targetAddress {
      if var symbolName = symbolResolver.symbol(at: targetAddr) {
        if options.demangleSwift && swiftDemangler.isSwiftSymbol(symbolName) {
          symbolName = swiftDemangler.demangle(symbolName)
        }
        result = result.withTargetSymbol(symbolName)
      }
    }

    // Annotate PAC instructions
    if options.annotatePAC {
      result = pacAnnotator.annotateInstruction(result)
    }

    return result
  }

  /// Find the end address of a function
  private func findFunctionEnd(
    startAddress: UInt64,
    in binary: MachOBinary,
    sectionEnd: UInt64
  ) -> UInt64 {
    // Look for the next symbol after this address
    var nextSymbolAddress = sectionEnd

    if let symbols = binary.symbols {
      for symbol in symbols {
        if symbol.address > startAddress && symbol.address < nextSymbolAddress {
          nextSymbolAddress = symbol.address
        }
      }
    }

    return nextSymbolAddress
  }

  /// Find the section containing an address
  private func findSection(
    containing address: UInt64,
    in binary: MachOBinary
  ) -> (Section, Data)? {
    for segment in binary.segments {
      for section in segment.sections {
        guard let data = try? binary.readSectionData(section) else { continue }

        let sectionStart = section.address
        let sectionEnd = sectionStart + UInt64(data.count)

        if address >= sectionStart && address < sectionEnd {
          return (section, data)
        }
      }
    }
    return nil
  }
}

// MARK: - Convenience Extensions

extension ARM64Disassembler {
  /// Disassemble the __text section
  public func disassembleTextSection(from binary: MachOBinary) throws -> DisassemblyResult {
    guard let textSection = binary.section(segment: "__TEXT", section: "__text") else {
      throw DisassemblyError.sectionNotFound(name: "__text")
    }
    return try disassembleSection(textSection, from: binary)
  }

  /// List all functions in a binary
  public func listFunctions(in binary: MachOBinary) -> [(name: String, address: UInt64)] {
    var functions: [(name: String, address: UInt64)] = []

    // Get text section bounds
    guard let textSection = binary.section(segment: "__TEXT", section: "__text"),
      let textData = try? binary.readSectionData(textSection)
    else {
      return []
    }

    let textStart = textSection.address
    let textEnd = textStart + UInt64(textData.count)

    // Find symbols in the text section
    guard let symbols = binary.symbols else {
      return []
    }

    for symbol in symbols {
      if symbol.address >= textStart && symbol.address < textEnd {
        var name = symbol.name
        if options.demangleSwift && swiftDemangler.isSwiftSymbol(name) {
          name = swiftDemangler.demangle(name)
        }
        functions.append((name: name, address: symbol.address))
      }
    }

    // Sort by address
    functions.sort { $0.address < $1.address }

    return functions
  }
}
