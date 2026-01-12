// ParseCommand.swift
// MachScope
//
// Parse Mach-O binary command

import Foundation
import MachOKit

/// Parse command implementation
public struct ParseCommand: Sendable {

  /// Execute the parse command
  /// - Parameters:
  ///   - args: Parsed command-line arguments
  /// - Returns: Exit code (0 for success)
  public static func execute(args: ParsedArguments) -> Int32 {
    // Get binary path
    guard let binaryPath = args.positional.first else {
      printParseUsage()
      return 1
    }

    // Determine output format
    let useJSON = args.hasFlag("json") || args.hasFlag("j")

    // Determine color mode
    let colorModeString = args.option("color") ?? "auto"
    let colorMode: ColorMode
    switch colorModeString.lowercased() {
    case "always":
      colorMode = .always
    case "never":
      colorMode = .never
    default:
      colorMode = .auto
    }

    // Determine what to show
    let options = FormatOptions(
      showHeaders: args.hasFlag("all") || args.hasFlag("headers") || !hasAnyDetailFlag(args),
      showLoadCommands: args.hasFlag("all") || args.hasFlag("load-commands"),
      showSegments: args.hasFlag("all") || args.hasFlag("segments") || !hasAnyDetailFlag(args),
      showSymbols: args.hasFlag("all") || args.hasFlag("symbols"),
      showDylibs: args.hasFlag("all") || args.hasFlag("dylibs") || !hasAnyDetailFlag(args),
      showStrings: args.hasFlag("all") || args.hasFlag("strings"),
      showSignature: args.hasFlag("all") || args.hasFlag("signatures") || args.hasFlag("signature"),
      showEntitlements: args.hasFlag("all") || args.hasFlag("entitlements")
    )

    // Determine architecture
    let archString = args.option("arch") ?? "arm64"
    let architecture = CPUType.from(string: archString) ?? .arm64

    do {
      // Check file size for progress indication
      let fileManager = FileManager.default
      if let attrs = try? fileManager.attributesOfItem(atPath: binaryPath),
        let fileSize = attrs[.size] as? UInt64,
        fileSize > 10 * 1024 * 1024
      {  // 10MB threshold
        if !useJSON {
          fputs("Parsing large binary (\(formatFileSize(fileSize)))...\n", stderr)
        }
      }

      // Parse the binary
      let binary = try MachOBinary(path: binaryPath, architecture: architecture)

      // Format output
      let output: String
      if useJSON {
        let formatter = JSONFormatter()
        output = formatter.format(binary, options: options)
      } else {
        let formatter = TextFormatter(colorMode: colorMode)
        output = formatter.format(binary, options: options)
      }

      print(output)
      return 0

    } catch let error as MachOParseError {
      fputs("Error: \(error.localizedDescription)\n", stderr)
      return exitCode(for: error)
    } catch {
      fputs("Error: \(error.localizedDescription)\n", stderr)
      return 4  // Generic parse error
    }
  }

  /// Format file size for display
  private static func formatFileSize(_ bytes: UInt64) -> String {
    if bytes >= 1024 * 1024 * 1024 {
      return String(format: "%.2f GB", Double(bytes) / (1024 * 1024 * 1024))
    } else if bytes >= 1024 * 1024 {
      return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    } else if bytes >= 1024 {
      return String(format: "%.1f KB", Double(bytes) / 1024)
    } else {
      return "\(bytes) bytes"
    }
  }

  /// Map MachOParseError to exit code per cli-interface.md
  private static func exitCode(for error: MachOParseError) -> Int32 {
    switch error {
    case .fileNotFound, .fileAccessError:
      return 1
    case .invalidMagic, .invalidFatMagic, .truncatedHeader, .emptyFatBinary:
      return 2
    case .architectureNotFound, .unsupportedCPUType:
      return 3
    case .insufficientData, .loadCommandSizeMismatch, .invalidLoadCommandSize,
      .segmentOutOfBounds, .sectionOutOfBounds, .symbolNotFound,
      .invalidCodeSignatureMagic, .invalidCodeSignatureLength,
      .codeSignatureNotFound, .invalidEntitlementsFormat, .custom:
      return 4  // Parse error (corrupted binary)
    }
  }

  /// Check if any specific detail flag is set
  private static func hasAnyDetailFlag(_ args: ParsedArguments) -> Bool {
    args.hasFlag("headers") || args.hasFlag("load-commands") || args.hasFlag("segments")
      || args.hasFlag("symbols") || args.hasFlag("dylibs") || args.hasFlag("strings")
      || args.hasFlag("signatures") || args.hasFlag("signature") || args.hasFlag("entitlements")
  }

  /// Print parse command usage
  private static func printParseUsage() {
    print(
      """
      USAGE:
          machscope parse <binary> [options]

      ARGUMENTS:
          <binary>                    Path to Mach-O binary file

      OPTIONS:
          --json, -j                  Output in JSON format
          --arch <arch>               Architecture to parse (arm64, x86_64)
          --color <mode>              Color output: auto, always, never
          --all                       Show all information
          --headers                   Show Mach-O header
          --load-commands             Show load commands summary
          --segments                  Show segments and sections
          --symbols                   Show symbol table
          --strings                   Show extracted strings
          --dylibs                    Show dynamic library dependencies
          --signatures                Show code signature information
          --entitlements              Show embedded entitlements

      EXAMPLES:
          machscope parse /bin/ls
          machscope parse /bin/ls --json
          machscope parse /bin/ls --all
          machscope parse /bin/ls --symbols --dylibs
          machscope parse /bin/ls --symbols --strings --json
      """)
  }
}

// MARK: - CPUType Extension

extension CPUType {
  /// Create CPUType from string
  static func from(string: String) -> CPUType? {
    switch string.lowercased() {
    case "arm64", "aarch64":
      return .arm64
    case "x86_64", "x64", "amd64":
      return .x86_64
    case "arm":
      return .arm
    case "i386", "x86", "i686":
      return .x86
    default:
      return nil
    }
  }
}
