// SIPDetector.swift
// DebuggerCore
//
// System Integrity Protection status detection

import Foundation

/// SIP (System Integrity Protection) status
public enum SIPStatus: Sendable, CustomStringConvertible {
  case enabled
  case disabled
  case unknown

  public var description: String {
    switch self {
    case .enabled: return "Enabled"
    case .disabled: return "Disabled"
    case .unknown: return "Unknown"
    }
  }
}

/// Detects System Integrity Protection status and protected paths
public struct SIPDetector: Sendable {

  /// Cached SIP status (detected once)
  private let cachedStatus: SIPStatus

  public init() {
    self.cachedStatus = SIPDetector.detectSIPStatus()
  }

  /// Current SIP status
  public var sipStatus: SIPStatus {
    cachedStatus
  }

  /// Whether SIP is enabled
  public var isEnabled: Bool {
    sipStatus == .enabled
  }

  /// Check if SIP blocks debugging a specific path
  /// - Parameter path: Path to the binary
  /// - Returns: true if SIP would block debugging this binary
  public func blocksDebugging(path: String) -> Bool {
    guard isEnabled else { return false }
    return SIPDetector.isProtectedPath(path)
  }

  /// Guidance for disabling SIP (for advanced users)
  public var disableGuidance: String {
    """
    To disable SIP (not recommended):
    1. Restart your Mac and hold Command+R during boot
    2. In Recovery Mode, open Terminal from Utilities menu
    3. Run: csrutil disable
    4. Restart your Mac

    Warning: Disabling SIP reduces system security.
    """
  }

  // MARK: - Static Methods

  /// Check if a path is SIP-protected
  /// - Parameter path: The file path to check
  /// - Returns: true if the path is under SIP protection
  public static func isProtectedPath(_ path: String) -> Bool {
    let protectedPrefixes = [
      "/bin/",
      "/sbin/",
      "/usr/bin/",
      "/usr/sbin/",
      "/usr/lib/",
      "/usr/libexec/",
      "/usr/share/",
      "/System/",
    ]

    // Normalize the path
    let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"

    // Check against protected prefixes
    for prefix in protectedPrefixes {
      if normalizedPath.hasPrefix(prefix) {
        // Exception: /usr/local is NOT protected
        if normalizedPath.hasPrefix("/usr/local/") {
          return false
        }
        return true
      }
    }

    return false
  }

  // MARK: - Private Methods

  /// Detect SIP status using csrutil
  private static func detectSIPStatus() -> SIPStatus {
    // Use csrutil to check SIP status
    let process = Process()
    let pipe = Pipe()

    process.executableURL = URL(fileURLWithPath: "/usr/bin/csrutil")
    process.arguments = ["status"]
    process.standardOutput = pipe
    process.standardError = pipe

    do {
      try process.run()
      process.waitUntilExit()

      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      guard let output = String(data: data, encoding: .utf8) else {
        return .unknown
      }

      // Parse csrutil output
      // "System Integrity Protection status: enabled."
      // "System Integrity Protection status: disabled."
      if output.lowercased().contains("enabled") {
        return .enabled
      } else if output.lowercased().contains("disabled") {
        return .disabled
      } else {
        return .unknown
      }
    } catch {
      // csrutil failed, try alternative detection
      return detectSIPStatusAlternative()
    }
  }

  /// Alternative SIP detection method (file-based check)
  private static func detectSIPStatusAlternative() -> SIPStatus {
    // If we can write to a SIP-protected location, SIP is disabled
    // We don't actually write, just check permissions conceptually
    // Instead, we'll check if /System is read-only (typical when SIP enabled)

    let fileManager = FileManager.default

    // Try to check if /System/Library is writable
    // When SIP is enabled, this will be false even for root
    // We can't actually test write permissions reliably without root
    // So we default to enabled (the safe assumption)
    if fileManager.isWritableFile(atPath: "/System/Library") {
      return .disabled
    }

    // Default: assume SIP is enabled (safer assumption)
    return .enabled
  }
}

// MARK: - Debug Description

extension SIPDetector: CustomDebugStringConvertible {
  public var debugDescription: String {
    "SIPDetector(status: \(sipStatus))"
  }
}
