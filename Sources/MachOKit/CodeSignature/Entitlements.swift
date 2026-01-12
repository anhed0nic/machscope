// Entitlements.swift
// MachOKit
//
// Entitlements parser (XML and DER)

import Foundation

/// Parsed entitlements from code signature
///
/// Entitlements are embedded as either XML plist or DER-encoded format.
/// This struct provides access to both the raw data and parsed key-value pairs.
///
/// Note: Uses @unchecked Sendable because plist entries contain value types only
/// (String, Bool, Number, Array, Dictionary, Data) which are effectively Sendable.
public struct Entitlements: @unchecked Sendable {
  /// Raw XML string (if available)
  public let rawXML: String?

  /// Raw DER data (if available)
  public let rawDER: Data?

  /// Parsed entitlements dictionary
  public let entries: [String: Any]

  /// Source format of the entitlements
  public let format: EntitlementsFormat

  /// Whether any entitlements were found
  public var isEmpty: Bool {
    entries.isEmpty
  }

  /// Number of entitlements
  public var count: Int {
    entries.count
  }

  /// Parse entitlements from XML blob data
  /// - Parameter data: Raw XML plist data (from entitlements blob, excluding header)
  /// - Returns: Parsed Entitlements
  /// - Throws: MachOParseError if parsing fails
  public static func parseXML(from data: Data) throws -> Entitlements {
    // Convert to string first
    guard let xmlString = String(data: data, encoding: .utf8) else {
      throw MachOParseError.invalidEntitlementsFormat(reason: "Cannot decode XML as UTF-8")
    }

    // Parse as property list
    do {
      guard
        let plist = try PropertyListSerialization.propertyList(
          from: data,
          options: [],
          format: nil
        ) as? [String: Any]
      else {
        throw MachOParseError.invalidEntitlementsFormat(reason: "Root element is not a dictionary")
      }

      return Entitlements(
        rawXML: xmlString,
        rawDER: nil,
        entries: plist,
        format: .xml
      )
    } catch let error as MachOParseError {
      throw error
    } catch {
      throw MachOParseError.invalidEntitlementsFormat(
        reason: "Invalid XML plist: \(error.localizedDescription)")
    }
  }

  /// Parse entitlements from DER blob data
  /// - Parameter data: Raw DER-encoded data (from DER entitlements blob, excluding header)
  /// - Returns: Parsed Entitlements (DER parsing is limited - we store raw data)
  /// - Throws: MachOParseError if parsing fails
  public static func parseDER(from data: Data) throws -> Entitlements {
    // DER parsing is complex and requires ASN.1 decoder
    // For now, we store the raw data and attempt to extract any text strings
    // Full DER parsing would require implementing an ASN.1 decoder

    // Try to parse as a property list (Apple sometimes uses bplist format)
    if let plist = try? PropertyListSerialization.propertyList(
      from: data,
      options: [],
      format: nil
    ) as? [String: Any] {
      return Entitlements(
        rawXML: nil,
        rawDER: data,
        entries: plist,
        format: .der
      )
    }

    // If not a plist, store raw DER with empty entries
    // Full DER parsing would extract the entitlements from ASN.1 structure
    return Entitlements(
      rawXML: nil,
      rawDER: data,
      entries: [:],
      format: .der
    )
  }

  /// Get a boolean entitlement value
  /// - Parameter key: Entitlement key
  /// - Returns: Boolean value, or nil if not found or not a boolean
  public func boolValue(for key: String) -> Bool? {
    entries[key] as? Bool
  }

  /// Get a string entitlement value
  /// - Parameter key: Entitlement key
  /// - Returns: String value, or nil if not found or not a string
  public func stringValue(for key: String) -> String? {
    entries[key] as? String
  }

  /// Get an array entitlement value
  /// - Parameter key: Entitlement key
  /// - Returns: Array value, or nil if not found or not an array
  public func arrayValue(for key: String) -> [Any]? {
    entries[key] as? [Any]
  }

  /// Get a dictionary entitlement value
  /// - Parameter key: Entitlement key
  /// - Returns: Dictionary value, or nil if not found or not a dictionary
  public func dictionaryValue(for key: String) -> [String: Any]? {
    entries[key] as? [String: Any]
  }

  /// Check if an entitlement key exists
  /// - Parameter key: Entitlement key
  /// - Returns: True if the key exists
  public func hasKey(_ key: String) -> Bool {
    entries[key] != nil
  }

  /// All entitlement keys
  public var keys: [String] {
    Array(entries.keys).sorted()
  }
}

// MARK: - Common Entitlement Keys

extension Entitlements {
  /// com.apple.security.cs.debugger - Debugger tool entitlement
  public var hasDebuggerEntitlement: Bool {
    boolValue(for: "com.apple.security.cs.debugger") ?? false
  }

  /// com.apple.security.get-task-allow - Allows debugging
  public var hasGetTaskAllow: Bool {
    boolValue(for: "com.apple.security.get-task-allow") ?? false
  }

  /// com.apple.security.app-sandbox - App Sandbox enabled
  public var isAppSandboxed: Bool {
    boolValue(for: "com.apple.security.app-sandbox") ?? false
  }

  /// com.apple.security.cs.allow-jit - Allows JIT compilation
  public var hasAllowJIT: Bool {
    boolValue(for: "com.apple.security.cs.allow-jit") ?? false
  }

  /// com.apple.security.cs.allow-unsigned-executable-memory
  public var hasAllowUnsignedMemory: Bool {
    boolValue(for: "com.apple.security.cs.allow-unsigned-executable-memory") ?? false
  }

  /// com.apple.security.cs.disable-library-validation
  public var hasDisableLibraryValidation: Bool {
    boolValue(for: "com.apple.security.cs.disable-library-validation") ?? false
  }

  /// com.apple.security.cs.allow-dyld-environment-variables
  public var hasAllowDyldEnv: Bool {
    boolValue(for: "com.apple.security.cs.allow-dyld-environment-variables") ?? false
  }

  /// com.apple.security.network.client - Network client access
  public var hasNetworkClient: Bool {
    boolValue(for: "com.apple.security.network.client") ?? false
  }

  /// com.apple.security.network.server - Network server access
  public var hasNetworkServer: Bool {
    boolValue(for: "com.apple.security.network.server") ?? false
  }

  /// com.apple.security.files.user-selected.read-only
  public var hasUserSelectedReadOnly: Bool {
    boolValue(for: "com.apple.security.files.user-selected.read-only") ?? false
  }

  /// com.apple.security.files.user-selected.read-write
  public var hasUserSelectedReadWrite: Bool {
    boolValue(for: "com.apple.security.files.user-selected.read-write") ?? false
  }

  /// application-identifier (iOS/Mac Catalyst)
  public var applicationIdentifier: String? {
    stringValue(for: "application-identifier")
  }

  /// com.apple.developer.team-identifier
  public var teamIdentifier: String? {
    stringValue(for: "com.apple.developer.team-identifier")
  }

  /// keychain-access-groups
  public var keychainAccessGroups: [String]? {
    arrayValue(for: "keychain-access-groups") as? [String]
  }
}

/// Entitlements source format
public enum EntitlementsFormat: String, Sendable, CustomStringConvertible {
  case xml
  case der

  public var description: String {
    rawValue.uppercased()
  }
}

// MARK: - CustomStringConvertible

extension Entitlements: CustomStringConvertible {
  public var description: String {
    var result = "Entitlements (\(format), \(count) entries):\n"
    for key in keys {
      let value = entries[key]
      result += "  \(key): \(formatValue(value))\n"
    }
    return result
  }

  private func formatValue(_ value: Any?) -> String {
    switch value {
    case let bool as Bool:
      return bool ? "true" : "false"
    case let string as String:
      return "\"\(string)\""
    case let array as [Any]:
      return "[\(array.count) items]"
    case let dict as [String: Any]:
      return "{\(dict.count) keys}"
    case let number as NSNumber:
      return number.stringValue
    default:
      return String(describing: value ?? "nil")
    }
  }
}
