// DisasmCommand.swift
// MachScope
//
// Disassemble ARM64 code command

import Disassembler
import Foundation
import MachOKit

/// Disassembly command implementation
public struct DisasmCommand: Sendable {

  /// Execute the disasm command
  /// - Parameters:
  ///   - args: Parsed command-line arguments
  /// - Returns: Exit code (0 for success)
  public static func execute(args: ParsedArguments) -> Int32 {
    // Get binary path
    guard let binaryPath = args.positional.first else {
      printDisasmUsage()
      return 1
    }

    // Determine output format
    let useJSON = args.hasFlag("json") || args.hasFlag("j")

    // Build disassembly options
    let disasmOptions = DisassemblyOptions(
      resolveSymbols: true,
      demangleSwift: !args.hasFlag("no-demangle"),
      annotatePAC: !args.hasFlag("no-pac"),
      showBytes: args.hasFlag("show-bytes") || args.hasFlag("b"),
      showAddresses: !args.hasFlag("no-address")
    )

    // Get optional parameters
    let functionName = args.option("function") ?? args.option("f")
    let addressString = args.option("address") ?? args.option("a")
    let sectionName = args.option("section") ?? "__text"
    let lengthString = args.option("length") ?? args.option("l")
    let instructionCount = lengthString.flatMap { Int($0) } ?? 100

    do {
      // Parse the binary
      let binary = try MachOBinary(path: binaryPath)

      // Create disassembler
      let disassembler = ARM64Disassembler(binary: binary, options: disasmOptions)

      // Determine what to disassemble
      let result: DisassemblyResult

      if let name = functionName {
        // Disassemble specific function
        result = try disassembler.disassembleFunction(name, from: binary)
      } else if let addrStr = addressString {
        // Disassemble from specific address
        guard let address = parseAddress(addrStr) else {
          fputs("Error: Invalid address format: \(addrStr)\n", stderr)
          return 6
        }

        // Calculate end address based on instruction count
        let endAddress = address + UInt64(instructionCount * 4)
        result = try disassembler.disassembleRange(from: address, to: endAddress, in: binary)
      } else if args.hasFlag("list-functions") {
        // List all functions
        let functions = disassembler.listFunctions(in: binary)
        if useJSON {
          printFunctionsJSON(functions)
        } else {
          printFunctionsText(functions)
        }
        return 0
      } else {
        // Disassemble section (default: __text)
        guard let section = binary.section(segment: "__TEXT", section: sectionName) else {
          fputs("Error: Section '\(sectionName)' not found\n", stderr)
          return 7
        }
        result = try disassembler.disassembleSection(section, from: binary)
      }

      // Format output
      if useJSON {
        printDisassemblyJSON(result, disassembler: disassembler)
      } else {
        printDisassemblyText(result, disassembler: disassembler, options: disasmOptions)
      }

      return 0

    } catch let error as MachOParseError {
      fputs("Error: \(error.localizedDescription)\n", stderr)
      return errorCode(for: error)
    } catch let error as DisassemblyError {
      fputs("Error: \(error.localizedDescription)\n", stderr)
      return errorCode(for: error)
    } catch {
      fputs("Error: \(error.localizedDescription)\n", stderr)
      return 1
    }
  }

  // MARK: - Output Formatting

  private static func printDisassemblyText(
    _ result: DisassemblyResult,
    disassembler: ARM64Disassembler,
    options: DisassemblyOptions
  ) {
    print("MachScope - Disassembly")
    print()

    if let funcName = result.functionName {
      print(
        "Function: \(funcName) (0x\(String(result.startAddress, radix: 16)) - 0x\(String(result.endAddress, radix: 16)))"
      )
    } else {
      print(
        "Address Range: 0x\(String(result.startAddress, radix: 16)) - 0x\(String(result.endAddress, radix: 16))"
      )
    }
    print()

    for instruction in result.instructions {
      let line = disassembler.format(instruction)
      print(line)
    }

    print()
    print("Total: \(result.count) instructions (\(result.byteCount) bytes)")
  }

  private static func printDisassemblyJSON(
    _ result: DisassemblyResult,
    disassembler: ARM64Disassembler
  ) {
    let formatter = InstructionFormatter()

    var dict: [String: Any] = [
      "startAddress": String(format: "0x%llx", result.startAddress),
      "endAddress": String(format: "0x%llx", result.endAddress),
      "instructionCount": result.count,
      "byteCount": result.byteCount,
    ]

    if let funcName = result.functionName {
      dict["function"] = funcName
    }

    dict["instructions"] = result.instructions.map { formatter.formatJSON($0) }

    if let jsonData = try? JSONSerialization.data(
      withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
      let jsonString = String(data: jsonData, encoding: .utf8)
    {
      print(jsonString)
    }
  }

  private static func printFunctionsText(_ functions: [(name: String, address: UInt64)]) {
    print("MachScope - Functions")
    print()

    if functions.isEmpty {
      print("No functions found in __TEXT,__text section")
      return
    }

    print(String(format: "%-18s %s", "Address", "Name"))
    print(String(repeating: "-", count: 60))

    for (name, address) in functions {
      print(String(format: "0x%016llx %@", address, name))
    }

    print()
    print("Total: \(functions.count) functions")
  }

  private static func printFunctionsJSON(_ functions: [(name: String, address: UInt64)]) {
    let list = functions.map { (name, address) -> [String: Any] in
      [
        "name": name,
        "address": String(format: "0x%llx", address),
      ]
    }

    let dict: [String: Any] = [
      "functions": list,
      "count": functions.count,
    ]

    if let jsonData = try? JSONSerialization.data(
      withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
      let jsonString = String(data: jsonData, encoding: .utf8)
    {
      print(jsonString)
    }
  }

  // MARK: - Helpers

  /// Parse address string (supports 0x prefix and decimal)
  private static func parseAddress(_ string: String) -> UInt64? {
    let lowered = string.lowercased()
    if lowered.hasPrefix("0x") {
      return UInt64(String(lowered.dropFirst(2)), radix: 16)
    } else {
      return UInt64(string)
    }
  }

  /// Map MachOParseError to exit code
  private static func errorCode(for error: MachOParseError) -> Int32 {
    switch error {
    case .fileNotFound:
      return 1
    case .invalidMagic, .invalidFatMagic, .truncatedHeader:
      return 2
    case .architectureNotFound, .unsupportedCPUType:
      return 3
    default:
      return 4
    }
  }

  /// Map DisassemblyError to exit code
  private static func errorCode(for error: DisassemblyError) -> Int32 {
    switch error {
    case .symbolNotFound:
      return 5
    case .invalidAlignment, .addressOutOfRange, .invalidAddressRange:
      return 6
    case .sectionNotFound:
      return 7
    default:
      return 1
    }
  }

  /// Print disasm command usage
  private static func printDisasmUsage() {
    print(
      """
      USAGE:
          machscope disasm <binary> [options]

      ARGUMENTS:
          <binary>                    Path to Mach-O binary file

      OPTIONS:
          --json, -j                  Output in JSON format
          --function, -f <name>       Disassemble specific function
          --address, -a <addr>        Start address for disassembly
          --length, -l <count>        Number of instructions (default: 100)
          --section <name>            Section to disassemble (default: __text)
          --show-bytes, -b            Show raw instruction bytes
          --no-address                Hide instruction addresses
          --no-demangle               Don't demangle Swift symbols
          --no-pac                    Don't annotate PAC instructions
          --list-functions            List all functions in binary

      EXAMPLES:
          machscope disasm /bin/ls
          machscope disasm /bin/ls --function _main
          machscope disasm /bin/ls --address 0x100003f40 --length 20
          machscope disasm /bin/ls --list-functions
          machscope disasm /bin/ls --json --function _main
      """)
  }
}
