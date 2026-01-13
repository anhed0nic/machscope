// ArgumentParser.swift
// MachScope
//
// CLI argument parsing

import Foundation

/// Parsed command-line arguments
public struct ParsedArguments: Sendable {
  /// Command to execute
  public let command: String

  /// Positional arguments (after command)
  public let positional: [String]

  /// Flag options (--json, --verbose, etc.)
  public let flags: Set<String>

  /// Key-value options (--arch arm64, --function _main)
  public let options: [String: String]

  /// Check if a flag is present
  public func hasFlag(_ name: String) -> Bool {
    flags.contains(name) || flags.contains("-\(name)")
  }

  /// Get an option value
  public func option(_ name: String) -> String? {
    options[name] ?? options["-\(name)"]
  }
}

/// CLI argument parser
public struct ArgumentParser: Sendable {
  private let args: [String]

  public init(args: [String] = CommandLine.arguments) {
    self.args = args
  }

  /// Parse command-line arguments
  /// - Returns: Parsed arguments
  public func parse() -> ParsedArguments {
    var command = ""
    var positional: [String] = []
    var flags: Set<String> = []
    var options: [String: String] = [:]

    // Skip the program name (args[0])
    var index = 1

    // First non-option argument is the command
    while index < args.count {
      let arg = args[index]

      if arg.hasPrefix("-") {
        break
      }

      if command.isEmpty {
        command = arg
      } else {
        positional.append(arg)
      }

      index += 1
    }

    // Process remaining arguments
    while index < args.count {
      let arg = args[index]

      if arg.hasPrefix("--") {
        // Long option
        let optionName = String(arg.dropFirst(2))

        if optionName.contains("=") {
          // --option=value
          let parts = optionName.split(separator: "=", maxSplits: 1)
          options[String(parts[0])] = String(parts[1])
        } else if index + 1 < args.count && !args[index + 1].hasPrefix("-") {
          // --option value (but only if next arg isn't a flag)
          // Check if this is a boolean flag
          if isBooleanFlag(optionName) {
            flags.insert(optionName)
          } else {
            options[optionName] = args[index + 1]
            index += 1
          }
        } else {
          // Boolean flag
          flags.insert(optionName)
        }
      } else if arg.hasPrefix("-") && arg.count == 2 {
        // Short option (-j, -v, etc.)
        let optionName = String(arg.dropFirst(1))
        flags.insert(optionName)
      } else {
        // Positional argument after options
        positional.append(arg)
      }

      index += 1
    }

    return ParsedArguments(
      command: command,
      positional: positional,
      flags: flags,
      options: options
    )
  }

  /// Check if an option name is a boolean flag
  private func isBooleanFlag(_ name: String) -> Bool {
    let booleanFlags = [
      // General flags
      "json", "verbose", "v", "help", "h", "version",
      // Parse command flags
      "all", "headers", "load-commands",
      "segments", "sections", "symbols", "dylibs",
      "strings", "signatures", "signature", "entitlements",
      // Disasm command flags
      "show-bytes", "b", "no-address", "no-demangle", "no-pac",
      "list-functions",
    ]
    return booleanFlags.contains(name)
  }
}
