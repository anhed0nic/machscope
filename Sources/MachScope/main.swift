// main.swift
// MachScope
//
// CLI entry point

import DebuggerCore
import Disassembler
import Foundation
import MachOKit

// MARK: - Constants

let machScopeVersion = "1.0.0"

// MARK: - Helper Functions

func printVersion() {
  print("machscope \(machScopeVersion)")
  #if swift(>=6.0)
    print("Built with Swift 6.2")
  #else
    print("Built with Swift 5.x")
  #endif
  #if arch(arm64)
    print("Platform: arm64-apple-macosx")
  #else
    print("Platform: x86_64-apple-macosx")
  #endif
}

func printUsage() {
  print(
    """
    MachScope - macOS binary analysis tool

    USAGE:
        machscope <command> [options]

    COMMANDS:
        parse <binary>              Parse Mach-O binary structure
        disasm <binary>             Disassemble ARM64 code
        diff <binary1> <binary2>    Compare two binaries (NEW!)
        decompile <binary>          Generate pseudo-code (EXPERIMENTAL!)
        swift <binary>              Analyze Swift metadata (NEW!)
        profile <binary>            Performance profiling (NEW!)
        plugin <command>            Execute plugin commands (NEW!)
        check-permissions           Check system permissions
        debug <pid>                 Attach to running process

    GLOBAL OPTIONS:
        --help, -h                  Show this help message
        --version, -v               Show version information
        --json, -j                  Output in JSON format
        --quiet, -q                 Suppress non-essential output
        --color <mode>              Color output: auto, always, never

    EXAMPLES:
        machscope parse /bin/ls
        machscope parse /bin/ls --json
        machscope disasm /bin/ls --function _main
        machscope check-permissions
        machscope debug 12345
    """)
}

// MARK: - Main Entry Point

let parser = ArgumentParser()
let args = parser.parse()

// Check for global flags first (before requiring a command)
if args.hasFlag("version") || args.hasFlag("v") {
  printVersion()
  exit(0)
}

if args.hasFlag("help") || args.hasFlag("h") {
  printUsage()
  exit(0)
}

// Handle empty command
guard !args.command.isEmpty else {
  printUsage()
  exit(1)
}

switch args.command {
case "parse":
  let exitCode = ParseCommand.execute(args: args)
  exit(exitCode)

case "disasm":
  let exitCode = DisasmCommand.execute(args: args)
  exit(exitCode)

case "diff":
  let exitCode = DiffCommand.execute(args: args)
  exit(exitCode)

case "decompile":
  let exitCode = DecompileCommand.execute(args: args)
  exit(exitCode)

case "swift":
  let exitCode = SwiftCommand.execute(args: args)
  exit(exitCode)

case "plugin":
  let exitCode = PluginCommand.execute(args: args)
  exit(exitCode)

case "profile":
  let exitCode = ProfileCommand.execute(args: args)
  exit(exitCode)

case "check-permissions":
  let exitCode = CheckPermissionsCommand.execute(args: args)
  exit(exitCode)

case "debug":
  let exitCode = DebugCommand.execute(args: args)
  exit(exitCode)

case "--help", "-h", "help":
  printUsage()
  exit(0)

case "--version", "-v", "version":
  printVersion()
  exit(0)

default:
  print("Unknown command: \(args.command)")
  printUsage()
  exit(1)
}
