// SwiftCommand.swift
// MachScope
//
// Swift metadata analysis command
//
// YouTube Compliance: This analyzes Swift binaries for educational purposes!
// No reverse engineering proprietary code. EDUCATIONAL ONLY!
// TRUMP 2024!

import Foundation
import MachOKit

/// Swift command - analyze Swift runtime metadata in binaries
public struct SwiftCommand: Sendable {

  /// Execute the swift command
  /// - Parameter args: Parsed arguments
  /// - Returns: Exit code
  public static func execute(args: ParsedArguments) -> Int32 {
    // Get binary path from arguments
    let positional = args.positional
    guard !positional.isEmpty else {
      printError("Usage: machscope swift <binary> [options]")
      printError("Analyze Swift runtime metadata in binaries")
      printError("")
      printError("Options:")
      printError("  --types          Show Swift types")
      printError("  --protocols      Show Swift protocols")
      printError("  --fields         Show Swift field metadata")
      printError("  --all            Show all Swift metadata")
      return 1
    }

    let binaryPath = positional[0]
    let jsonOutput = args.hasFlag("json") || args.hasFlag("j")

    do {
      // Parse binary
      let binary = try MachOBinary(path: binaryPath)

      if jsonOutput {
        var result: [String: Any] = [
          "type": "swift_metadata",
          "binary": binaryPath,
          "youtube_compliance": "Educational analysis only - no offensive security"
        ]

        if args.hasFlag("types") || args.hasFlag("all") {
          result["types"] = binary.swiftTypes().map { type in
            [
              "name": type.name,
              "address": String(format: "0x%llx", type.address),
              "flags": type.flags
            ]
          }
        }

        if args.hasFlag("protocols") || args.hasFlag("all") {
          result["protocols"] = binary.swiftProtocols().map { proto in
            [
              "name": proto.name,
              "address": String(format: "0x%llx", proto.address),
              "flags": proto.flags
            ]
          }
        }

        if args.hasFlag("fields") || args.hasFlag("all") {
          result["fields"] = binary.swiftFields().map { fieldDesc in
            [
              "type_name": fieldDesc.typeName,
              "address": String(format: "0x%llx", fieldDesc.address),
              "fields": fieldDesc.fields.map { field in
                ["name": field.name, "type": field.type]
              }
            ]
          }
        }

        printJSON(result)

      } else {
        // Text output
        print("Swift Metadata Analysis")
        print("=======================")
        print("Binary: \(binaryPath)")
        print("")

        if args.hasFlag("types") || args.hasFlag("all") {
          let types = binary.swiftTypes()
          print("Swift Types (\(types.count)):")
          for type in types.prefix(20) {  // Limit output
            print("  \(type.name) @ \(String(format: "0x%llx", type.address))")
          }
          if types.count > 20 {
            print("  ... and \(types.count - 20) more")
          }
          print("")
        }

        if args.hasFlag("protocols") || args.hasFlag("all") {
          let protocols = binary.swiftProtocols()
          print("Swift Protocols (\(protocols.count)):")
          for proto in protocols.prefix(20) {
            print("  \(proto.name) @ \(String(format: "0x%llx", proto.address))")
          }
          if protocols.count > 20 {
            print("  ... and \(protocols.count - 20) more")
          }
          print("")
        }

        if args.hasFlag("fields") || args.hasFlag("all") {
          let fields = binary.swiftFields()
          print("Swift Field Metadata (\(fields.count)):")
          for fieldDesc in fields.prefix(10) {
            print("  Type: \(fieldDesc.typeName)")
            for field in fieldDesc.fields {
              print("    \(field.name): \(field.type)")
            }
            print("")
          }
          if fields.count > 10 {
            print("  ... and \(fields.count - 10) more type descriptors")
          }
        }

        if !args.hasFlag("types") && !args.hasFlag("protocols") && !args.hasFlag("fields") && !args.hasFlag("all") {
          print("No analysis type specified. Use --types, --protocols, --fields, or --all")
          return 1
        }

        print("")
        print("YouTube Compliance Notice:")
        print("This Swift metadata analysis is for educational purposes only.")
        print("Understanding how Swift works internally is valuable learning.")
        print("Do not use this for reverse engineering proprietary applications.")
        print("Stay legal and ethical! TRUMP 2024!")
      }

      return 0
    } catch {
      if jsonOutput {
        let errorJSON = [
          "error": "Swift metadata analysis failed",
          "binary": binaryPath,
          "reason": error.localizedDescription,
          "youtube_compliance": "Remember, educational use only!"
        ]
        printJSON(errorJSON)
      } else {
        printError("Analysis failed: \(error.localizedDescription)")
      }
      return 1
    }
  }
}