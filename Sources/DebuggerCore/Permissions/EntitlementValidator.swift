// EntitlementValidator.swift
// DebuggerCore
//
// Debugger entitlement check

import Foundation
import Security

/// Validates debugger entitlements and Developer Tools access
public struct EntitlementValidator: Sendable {

  /// The debugger entitlement key
  public static let debuggerEntitlement = "com.apple.security.cs.debugger"

  /// The get-task-allow entitlement key (for debug targets)
  public static let getTaskAllowEntitlement = "get-task-allow"

  public init() {}

  // MARK: - Entitlement Checking

  /// Check if the current process has debugger entitlement
  /// - Parameter forCurrentProcess: If true, checks the current process; otherwise checks the binary
  /// - Returns: true if the process has debugger entitlement
  public func hasDebuggerEntitlement(forCurrentProcess: Bool = true) -> Bool {
    if forCurrentProcess {
      return checkCurrentProcessEntitlement(Self.debuggerEntitlement)
    }
    return false
  }

  /// Check if a binary at the given path has get-task-allow entitlement
  /// - Parameter path: Path to the binary
  /// - Returns: true if the binary has get-task-allow
  public func hasGetTaskAllow(at path: String) -> Bool {
    return checkBinaryEntitlement(path: path, entitlement: Self.getTaskAllowEntitlement)
  }

  /// Check if Developer Tools are enabled in System Settings
  public var developerToolsEnabled: Bool {
    // Check if Developer Tools access is granted
    // This is typically indicated by whether we can use developer tools APIs

    // One way to check: see if we can access task_for_pid concepts
    // However, this is tricky without actually trying

    // Alternative: Check if DevToolsSecurity is authorized
    return checkDevToolsAuthorization()
  }

  // MARK: - Guidance

  /// Guidance for enabling debugger entitlement
  public var debuggerEntitlementGuidance: String {
    """
    To enable debugger entitlement:
    1. Sign the binary with: codesign --force --sign - --entitlements <entitlements.plist> <binary>
    2. Ensure entitlements.plist contains:
       <key>com.apple.security.cs.debugger</key>
       <true/>

    For development:
    1. Add the entitlement to your Xcode project's entitlements file
    2. Re-sign the application
    """
  }

  /// Guidance for enabling Developer Tools
  public var developerToolsGuidance: String {
    """
    To enable Developer Tools:
    1. Open System Settings > Privacy & Security > Developer Tools
    2. Enable access for Terminal (or your terminal app)
    3. Restart Terminal after enabling

    Deep link: x-apple.systempreferences:com.apple.preference.security?Privacy_DevTools
    """
  }

  /// System Settings deep link for Developer Tools
  public static let developerToolsDeepLink =
    "x-apple.systempreferences:com.apple.preference.security?Privacy_DevTools"

  // MARK: - Private Methods

  /// Check if current process has a specific entitlement using SecCode
  private func checkCurrentProcessEntitlement(_ entitlement: String) -> Bool {
    var code: SecCode?
    let status = SecCodeCopySelf([], &code)

    guard status == errSecSuccess, let secCode = code else {
      return false
    }

    // Get static code from dynamic code for signing information
    var staticCode: SecStaticCode?
    let staticStatus = SecCodeCopyStaticCode(secCode, [], &staticCode)

    guard staticStatus == errSecSuccess, let secStaticCode = staticCode else {
      return false
    }

    var info: CFDictionary?
    let infoStatus = SecCodeCopySigningInformation(
      secStaticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)

    guard infoStatus == errSecSuccess, let signingInfo = info as? [String: Any] else {
      return false
    }

    // Get entitlements dictionary
    if let entitlements = signingInfo[kSecCodeInfoEntitlementsDict as String] as? [String: Any] {
      if let value = entitlements[entitlement] as? Bool {
        return value
      }
    }

    return false
  }

  /// Check if a binary has a specific entitlement
  private func checkBinaryEntitlement(path: String, entitlement: String) -> Bool {
    let url = URL(fileURLWithPath: path)
    var staticCode: SecStaticCode?

    let status = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)
    guard status == errSecSuccess, let code = staticCode else {
      return false
    }

    var info: CFDictionary?
    let infoStatus = SecCodeCopySigningInformation(
      code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)

    guard infoStatus == errSecSuccess, let signingInfo = info as? [String: Any] else {
      return false
    }

    // Get entitlements dictionary
    if let entitlements = signingInfo[kSecCodeInfoEntitlementsDict as String] as? [String: Any] {
      if let value = entitlements[entitlement] as? Bool {
        return value
      }
    }

    return false
  }

  /// Check if Developer Tools authorization is granted
  private func checkDevToolsAuthorization() -> Bool {
    // Check if we're running as root (root can debug)
    if getuid() == 0 {
      return true
    }

    // Check if DevToolsSecurity has authorized this process
    // This is the most reliable check for Developer Tools status
    return checkDevToolsSecurityAuthorization()
  }

  /// Check DevToolsSecurity authorization (alternative method)
  private func checkDevToolsSecurityAuthorization() -> Bool {
    // Run DevToolsSecurity tool to check status
    let process = Process()
    let pipe = Pipe()

    process.executableURL = URL(fileURLWithPath: "/usr/bin/DevToolsSecurity")
    process.arguments = ["-status"]
    process.standardOutput = pipe
    process.standardError = pipe

    do {
      try process.run()
      process.waitUntilExit()

      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      if let output = String(data: data, encoding: .utf8) {
        // "Developer mode is currently enabled."
        // "Developer mode is currently disabled."
        return output.lowercased().contains("enabled")
      }
    } catch {
      // Tool not available or failed
    }

    return false
  }
}

// MARK: - Debug Description

extension EntitlementValidator: CustomDebugStringConvertible {
  public var debugDescription: String {
    "EntitlementValidator(hasDebuggerEntitlement: \(hasDebuggerEntitlement()), developerToolsEnabled: \(developerToolsEnabled))"
  }
}
