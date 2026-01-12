// SwiftDemangler.swift
// Disassembler
//
// Swift symbol name demangling

import Foundation

/// Swift symbol demangler
public struct SwiftDemangler: Sendable {

  public init() {}

  // MARK: - Public API

  /// Demangle a Swift symbol name
  /// - Parameter name: The mangled symbol name
  /// - Returns: Demangled name, or original if not a Swift symbol
  public func demangle(_ name: String) -> String {
    // Check if this is a Swift symbol
    guard isSwiftSymbol(name) else {
      return name
    }

    // Try to demangle using the system demangler
    if let demangled = systemDemangle(name) {
      return demangled
    }

    // Fallback: basic Swift demangling
    return basicDemangle(name)
  }

  /// Check if a symbol is a Swift mangled name
  public func isSwiftSymbol(_ name: String) -> Bool {
    // Swift symbols start with _$s, $s, _$S, $S (Swift 5+)
    // or _T (Swift 4 and earlier)
    return name.hasPrefix("_$s") || name.hasPrefix("$s") || name.hasPrefix("_$S")
      || name.hasPrefix("$S") || name.hasPrefix("_T")
  }

  // MARK: - Private Helpers

  /// Use the system swift-demangle if available
  private func systemDemangle(_ name: String) -> String? {
    // Try using the swift-demangle tool
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/swift-demangle")
    process.arguments = [name]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
      process.waitUntilExit()

      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(
        in: .whitespacesAndNewlines)
      {
        // swift-demangle returns the input if it can't demangle
        if output != name && !output.isEmpty {
          return output
        }
      }
    } catch {
      // Tool not available or failed
    }

    return nil
  }

  /// Basic Swift demangling (simplified)
  private func basicDemangle(_ name: String) -> String {
    // Remove leading underscore if present
    var symbol = name
    if symbol.hasPrefix("_") {
      symbol = String(symbol.dropFirst())
    }

    // Check prefix
    guard symbol.hasPrefix("$s") || symbol.hasPrefix("$S") else {
      return name
    }

    // Remove Swift prefix
    symbol = String(symbol.dropFirst(2))

    // Basic demangling - just extract identifiable parts
    var result = ""
    var index = symbol.startIndex

    while index < symbol.endIndex {
      let char = symbol[index]

      // Check for length-prefixed identifier
      if char.isNumber {
        var lengthStr = ""
        while index < symbol.endIndex && symbol[index].isNumber {
          lengthStr.append(symbol[index])
          index = symbol.index(after: index)
        }

        if let length = Int(lengthStr), length > 0 {
          let endIndex = symbol.index(
            index, offsetBy: min(length, symbol.distance(from: index, to: symbol.endIndex)))
          let identifier = String(symbol[index..<endIndex])
          result += identifier
          index = endIndex
          continue
        }
      }

      // Handle special characters
      switch char {
      case "C":  // Class
        result += "."
      case "V":  // Struct
        result += "."
      case "O":  // Enum
        result += "."
      case "F":  // Function
        result += "("
      case "f":  // getter/setter
        result += " "
      case "s":  // Subscript
        result += "[]"
      case "i":  // Initializer
        result += "init"
      case "D":  // Deallocator
        result += "deinit"
      case "g":  // Getter
        result += ".get"
      case "w":  // Setter
        result += ".set"
      case "M":  // Metatype
        result += ".Type"
      case "S":  // Self
        result += "Self"
      default:
        break
      }

      index = symbol.index(after: index)
    }

    // Clean up result
    result = result.trimmingCharacters(in: CharacterSet(charactersIn: ".("))

    return result.isEmpty ? name : result
  }
}

// MARK: - SwiftDemangler Extensions

extension SwiftDemangler {
  /// Extract the module name from a Swift symbol
  public func moduleName(_ name: String) -> String? {
    guard isSwiftSymbol(name) else { return nil }

    // Module name is typically the first identifier after the prefix
    let demangled = demangle(name)
    let components = demangled.split(separator: ".")
    return components.first.map(String.init)
  }

  /// Extract the type name from a Swift symbol
  public func typeName(_ name: String) -> String? {
    guard isSwiftSymbol(name) else { return nil }

    let demangled = demangle(name)
    let components = demangled.split(separator: ".")

    // Type name is usually the second component
    if components.count >= 2 {
      return String(components[1])
    }

    return nil
  }

  /// Check if symbol represents a Swift type (class, struct, enum)
  public func isType(_ name: String) -> Bool {
    guard isSwiftSymbol(name) else { return false }

    // Look for type markers in the mangled name
    return name.contains("C")  // Class
      || name.contains("V")  // Struct
      || name.contains("O")  // Enum
  }

  /// Check if symbol represents a Swift function
  public func isFunction(_ name: String) -> Bool {
    guard isSwiftSymbol(name) else { return false }
    return name.contains("F")
  }
}
