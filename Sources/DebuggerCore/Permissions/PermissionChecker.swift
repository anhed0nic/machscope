// PermissionChecker.swift
// DebuggerCore
//
// Tiered capability detection

import Foundation

/// Permission tier representing available capabilities
public enum PermissionTier: Sendable, CustomStringConvertible {
  /// All features available (debugger entitlement + Developer Tools)
  case full

  /// Parse + Disassemble (no special permissions)
  case analysis

  /// Parse only (minimal permissions)
  case readOnly

  public var description: String {
    switch self {
    case .full: return "Full"
    case .analysis: return "Analysis"
    case .readOnly: return "Read-Only"
    }
  }

  /// Whether debugging is available at this tier
  public var canDebug: Bool {
    self == .full
  }

  /// Whether disassembly is available at this tier
  public var canDisassemble: Bool {
    self == .full || self == .analysis
  }

  /// Whether parsing is available at this tier
  public var canParse: Bool {
    true  // All tiers can parse
  }
}

/// Represents the complete permission status
public struct PermissionStatus: Sendable, Codable {
  public let staticAnalysis: Bool
  public let disassembly: Bool
  public let debugging: Bool
  public let sipEnabled: Bool
  public let developerToolsEnabled: Bool
  public let debuggerEntitlement: Bool

  public init(
    staticAnalysis: Bool,
    disassembly: Bool,
    debugging: Bool,
    sipEnabled: Bool,
    developerToolsEnabled: Bool,
    debuggerEntitlement: Bool
  ) {
    self.staticAnalysis = staticAnalysis
    self.disassembly = disassembly
    self.debugging = debugging
    self.sipEnabled = sipEnabled
    self.developerToolsEnabled = developerToolsEnabled
    self.debuggerEntitlement = debuggerEntitlement
  }

  /// Determine the permission tier from this status
  public var tier: PermissionTier {
    if debugging {
      return .full
    } else if disassembly {
      return .analysis
    } else {
      return .readOnly
    }
  }
}

/// Permission checker with tiered capability detection
public struct PermissionChecker: Sendable {

  /// SIP detector instance
  private let sipDetector: SIPDetector

  /// Entitlement validator instance
  private let entitlementValidator: EntitlementValidator

  public init() {
    self.sipDetector = SIPDetector()
    self.entitlementValidator = EntitlementValidator()
  }

  // MARK: - Tier Detection

  /// Current permission tier
  public var tier: PermissionTier {
    let status = self.status
    return status.tier
  }

  /// Whether debugging is available
  public var canDebug: Bool {
    tier == .full
  }

  /// Whether disassembly is available
  public var canDisassemble: Bool {
    tier.canDisassemble
  }

  /// Whether parsing is available
  public var canParse: Bool {
    tier.canParse
  }

  // MARK: - Status

  /// Complete permission status
  public var status: PermissionStatus {
    let hasDebuggerEntitlement = entitlementValidator.hasDebuggerEntitlement()
    let developerToolsEnabled = entitlementValidator.developerToolsEnabled
    let sipEnabled = sipDetector.isEnabled

    // Static analysis and disassembly always work (no special permissions)
    let staticAnalysis = true
    let disassembly = true

    // Debugging requires both debugger entitlement and developer tools
    let debugging = hasDebuggerEntitlement && developerToolsEnabled

    return PermissionStatus(
      staticAnalysis: staticAnalysis,
      disassembly: disassembly,
      debugging: debugging,
      sipEnabled: sipEnabled,
      developerToolsEnabled: developerToolsEnabled,
      debuggerEntitlement: hasDebuggerEntitlement
    )
  }

  /// Status dictionary for JSON output
  public var statusDictionary: [String: Bool] {
    let s = status
    return [
      "staticAnalysis": s.staticAnalysis,
      "disassembly": s.disassembly,
      "debugging": s.debugging,
      "sipEnabled": s.sipEnabled,
      "developerTools": s.developerToolsEnabled,
      "debuggerEntitlement": s.debuggerEntitlement,
    ]
  }

  // MARK: - Guidance

  /// Guidance text for enabling missing permissions
  public var guidance: String {
    let s = status
    var guidance: [String] = []

    if !s.debugging {
      if !s.developerToolsEnabled {
        guidance.append(
          """
          To enable Developer Tools:
            1. Open System Settings > Privacy & Security > Developer Tools
            2. Enable access for Terminal (or your terminal app)
            3. Restart Terminal after enabling
          """)
      }

      if !s.debuggerEntitlement {
        guidance.append(
          """
          To enable debugger entitlement:
            Run: codesign --force --sign - --entitlements Resources/MachScope.entitlements .build/debug/machscope
          """)
      }
    }

    if s.sipEnabled {
      guidance.append(
        """
        Note: System Integrity Protection is enabled.
          System binaries (under /bin, /usr/bin, /System) cannot be debugged.
        """)
    }

    if guidance.isEmpty {
      return "All permissions available. Full debugging capabilities enabled."
    }

    return guidance.joined(separator: "\n\n")
  }

  /// Detailed guidance for a specific permission
  public func guidanceFor(permission: String) -> String {
    switch permission.lowercased() {
    case "debugger", "debugging":
      return """
        To enable debugging:
        1. Enable Developer Tools in System Settings
        2. Sign MachScope with debugger entitlement
        3. Restart Terminal

        See 'machscope check-permissions' for detailed status.
        """
    case "developer", "developertools", "developer_tools":
      return entitlementValidator.developerToolsGuidance
    case "entitlement", "debuggerentitlement":
      return entitlementValidator.debuggerEntitlementGuidance
    case "sip":
      return sipDetector.disableGuidance
    default:
      return guidance
    }
  }

  // MARK: - Path-Specific Checks

  /// Check if debugging is blocked for a specific path
  /// - Parameter path: Path to the binary
  /// - Returns: Reason why debugging is blocked, or nil if allowed
  public func debuggingBlockedReason(for path: String) -> String? {
    // Check SIP first
    if sipDetector.blocksDebugging(path: path) {
      return "System Integrity Protection blocks debugging of system binaries"
    }

    // Check permissions
    if !canDebug {
      let s = status
      if !s.developerToolsEnabled {
        return "Developer Tools not enabled"
      }
      if !s.debuggerEntitlement {
        return "Debugger entitlement not present"
      }
    }

    return nil
  }

  // MARK: - Exit Code

  /// Exit code for CLI per cli-interface.md
  public var exitCode: Int32 {
    switch tier {
    case .full:
      return 0  // Full capabilities
    case .analysis:
      return 20  // Partial capabilities (analysis only)
    case .readOnly:
      return 21  // Minimal capabilities (parse only)
    }
  }
}

// MARK: - Debug Description

extension PermissionChecker: CustomDebugStringConvertible {
  public var debugDescription: String {
    "PermissionChecker(tier: \(tier), canDebug: \(canDebug))"
  }
}

// MARK: - Text Output Support

extension PermissionChecker {

  /// Pad a string to a given width
  private func pad(_ str: String, to width: Int) -> String {
    if str.count >= width {
      return str
    }
    return str + String(repeating: " ", count: width - str.count)
  }

  /// Format status for text output
  public var textOutput: String {
    let s = status

    var lines: [String] = []
    lines.append("MachScope Permission Check")
    lines.append("")
    lines.append("\(pad("Feature", to: 20))  \(pad("Status", to: 10))  Notes")
    lines.append(String(repeating: "-", count: 60))

    // Static Analysis
    lines.append(
      "\(pad("Static Analysis", to: 20))  \(pad(s.staticAnalysis ? "✓ Ready" : "✗ Denied", to: 10))  No special permissions needed"
    )

    // Disassembly
    lines.append(
      "\(pad("Disassembly", to: 20))  \(pad(s.disassembly ? "✓ Ready" : "✗ Denied", to: 10))  No special permissions needed"
    )

    // Debugger
    let debugStatus = s.debugging ? "✓ Ready" : "✗ Denied"
    var debugNote = ""
    if !s.debugging {
      if !s.debuggerEntitlement {
        debugNote = "Missing debugger entitlement"
      } else if !s.developerToolsEnabled {
        debugNote = "Developer Tools disabled"
      }
    }
    lines.append("\(pad("Debugger", to: 20))  \(pad(debugStatus, to: 10))  \(debugNote)")

    // Sub-items for debugger
    if !s.debugging {
      let devToolsStatus = s.developerToolsEnabled ? "✓ On" : "✗ Off"
      let devToolsNote = s.developerToolsEnabled ? "" : "Enable in System Settings"
      lines.append(
        "  → \(pad("Developer Tools", to: 16))  \(pad(devToolsStatus, to: 10))  \(devToolsNote)")

      let entitlementStatus = s.debuggerEntitlement ? "✓ Yes" : "✗ No"
      let entitlementNote = s.debuggerEntitlement ? "" : "Run codesign with entitlements"
      lines.append(
        "  → \(pad("Entitlement", to: 16))  \(pad(entitlementStatus, to: 10))  \(entitlementNote)")
    }

    lines.append("")
    lines.append("SIP Status: \(s.sipEnabled ? "Enabled" : "Disabled")")
    if s.sipEnabled {
      lines.append("  Note: System binaries cannot be debugged with SIP enabled")
    }

    lines.append("")
    lines.append("Capability Level: \(tier.description) (\(capabilityDescription))")

    // Add guidance if needed
    if !s.debugging {
      lines.append("")
      lines.append("To enable debugging:")
      if !s.developerToolsEnabled {
        lines.append("  1. Open System Settings > Privacy & Security > Developer Tools")
        lines.append("  2. Enable \"Terminal\" (or add MachScope if installed)")
        lines.append("  3. Restart Terminal")
      }
      if !s.debuggerEntitlement {
        lines.append(
          "  • Sign binary: codesign --force --sign - --entitlements Resources/MachScope.entitlements .build/debug/machscope"
        )
      }
    }

    return lines.joined(separator: "\n")
  }

  /// JSON output for --json flag
  public var jsonOutput: String {
    let s = status

    let output: [String: Any] = [
      "capabilities": [
        "staticAnalysis": s.staticAnalysis,
        "disassembly": s.disassembly,
        "debugging": s.debugging,
      ],
      "permissions": [
        "developerTools": s.developerToolsEnabled,
        "debuggerEntitlement": s.debuggerEntitlement,
        "sipEnabled": s.sipEnabled,
      ],
      "capabilityLevel": tier.description.lowercased(),
      "guidance": [
        "developerTools": [
          "path": "System Settings > Privacy & Security > Developer Tools",
          "deepLink": EntitlementValidator.developerToolsDeepLink,
        ]
      ],
    ]

    // Manually build JSON (to avoid depending on JSONSerialization ordering)
    return buildJSON(output)
  }

  private var capabilityDescription: String {
    switch tier {
    case .full:
      return "parse + disasm + debug"
    case .analysis:
      return "parse + disasm only"
    case .readOnly:
      return "parse only"
    }
  }

  private func buildJSON(_ dict: [String: Any], indent: Int = 0) -> String {
    let indentStr = String(repeating: "  ", count: indent)
    let nextIndent = String(repeating: "  ", count: indent + 1)

    var lines: [String] = ["{"]

    let keys = dict.keys.sorted()
    for (idx, key) in keys.enumerated() {
      let value = dict[key]!
      let comma = idx < keys.count - 1 ? "," : ""

      if let boolValue = value as? Bool {
        lines.append("\(nextIndent)\"\(key)\": \(boolValue)\(comma)")
      } else if let stringValue = value as? String {
        lines.append("\(nextIndent)\"\(key)\": \"\(stringValue)\"\(comma)")
      } else if let dictValue = value as? [String: Any] {
        let nested = buildJSON(dictValue, indent: indent + 1)
          .split(separator: "\n")
          .joined(separator: "\n\(nextIndent)")
        lines.append("\(nextIndent)\"\(key)\": \(nested)\(comma)")
      }
    }

    lines.append("\(indentStr)}")
    return lines.joined(separator: "\n")
  }
}
