// CheckPermissionsCommand.swift
// MachScope
//
// Check system permissions command

import DebuggerCore
import Foundation

/// Check permissions command implementation
public struct CheckPermissionsCommand: Sendable {

  /// Execute the check-permissions command
  /// - Parameters:
  ///   - args: Parsed command-line arguments
  /// - Returns: Exit code (0 for full, 20 for partial, 21 for minimal)
  public static func execute(args: ParsedArguments) -> Int32 {
    // Determine output format
    let useJSON = args.hasFlag("json") || args.hasFlag("j")
    let verbose = args.hasFlag("verbose") || args.hasFlag("v")

    // Create permission checker
    let checker = PermissionChecker()

    // Format output
    if useJSON {
      print(checker.jsonOutput)
    } else {
      print(checker.textOutput)

      // If verbose, add additional information
      if verbose {
        printVerboseInfo(checker)
      }
    }

    return checker.exitCode
  }

  /// Print verbose information about permissions
  private static func printVerboseInfo(_ checker: PermissionChecker) {
    print("")
    print("=== Verbose Information ===")
    print("")

    // SIP details
    let sipDetector = SIPDetector()
    print("SIP Detection Method: csrutil status")
    print("SIP Status: \(sipDetector.sipStatus)")
    print("")

    // Protected paths
    print("Protected Paths (when SIP enabled):")
    let protectedPaths = ["/bin", "/sbin", "/usr/bin", "/usr/lib", "/System"]
    for path in protectedPaths {
      print("  - \(path)/")
    }
    print("  (Exception: /usr/local is NOT protected)")
    print("")

    // Entitlement details
    print("Entitlement Details:")
    print("  - Debugger entitlement key: \(EntitlementValidator.debuggerEntitlement)")
    print("  - Target entitlement key: \(EntitlementValidator.getTaskAllowEntitlement)")
    print("  - Developer Tools deep link: \(EntitlementValidator.developerToolsDeepLink)")
    print("")

    // Codesign command
    print("To sign MachScope with debugger entitlement:")
    print(
      "  codesign --force --sign - --entitlements Resources/MachScope.entitlements .build/debug/machscope"
    )
    print("")

    // Current state
    print("Current Permission State:")
    let status = checker.status
    print("  - Static Analysis: \(status.staticAnalysis ? "Available" : "Unavailable")")
    print("  - Disassembly: \(status.disassembly ? "Available" : "Unavailable")")
    print("  - Debugging: \(status.debugging ? "Available" : "Unavailable")")
    print("  - SIP Enabled: \(status.sipEnabled)")
    print("  - Developer Tools: \(status.developerToolsEnabled ? "Enabled" : "Disabled")")
    print("  - Debugger Entitlement: \(status.debuggerEntitlement ? "Present" : "Missing")")
  }

  /// Print check-permissions command usage
  public static func printUsage() {
    print(
      """
      USAGE:
          machscope check-permissions [options]

      OPTIONS:
          --json, -j                  Output in JSON format
          --verbose, -v               Show detailed information

      EXIT CODES:
          0                           Full capabilities available
          20                          Partial capabilities (analysis only)
          21                          Minimal capabilities (parse only)

      EXAMPLES:
          machscope check-permissions
          machscope check-permissions --json
          machscope check-permissions --verbose
      """)
  }
}
