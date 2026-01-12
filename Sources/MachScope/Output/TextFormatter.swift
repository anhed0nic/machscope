// TextFormatter.swift
// MachScope
//
// Human-readable text output formatter

import Foundation
import MachOKit

/// Color output mode
public enum ColorMode: String, Sendable {
  case auto = "auto"
  case always = "always"
  case never = "never"

  /// Determine if colors should be used based on mode and environment
  public var shouldUseColors: Bool {
    switch self {
    case .always:
      return true
    case .never:
      return false
    case .auto:
      // Check for NO_COLOR environment variable (standard)
      if ProcessInfo.processInfo.environment["NO_COLOR"] != nil {
        return false
      }
      // Check for MACHSCOPE_COLOR override
      if let override = ProcessInfo.processInfo.environment["MACHSCOPE_COLOR"] {
        return override.lowercased() != "never" && override != "0"
      }
      // Auto-detect: check if output is a TTY
      return isatty(STDOUT_FILENO) != 0
    }
  }
}

/// ANSI color codes for terminal output
public struct ANSIColors: Sendable {
  public static let reset = "\u{001B}[0m"
  public static let bold = "\u{001B}[1m"

  // Foreground colors
  public static let red = "\u{001B}[31m"
  public static let green = "\u{001B}[32m"
  public static let yellow = "\u{001B}[33m"
  public static let blue = "\u{001B}[34m"
  public static let magenta = "\u{001B}[35m"
  public static let cyan = "\u{001B}[36m"
  public static let white = "\u{001B}[37m"
  public static let gray = "\u{001B}[90m"

  // Semantic colors
  public static let header = bold + cyan
  public static let subheader = bold + white
  public static let address = yellow
  public static let symbol = green
  public static let error = bold + red
  public static let warning = yellow
  public static let success = green
  public static let info = blue
  public static let dim = gray
}

/// Text formatter for human-readable output
public struct TextFormatter: Sendable {
  /// Color mode for output
  public let colorMode: ColorMode

  /// Whether to use colors (computed from colorMode)
  public var useColors: Bool {
    colorMode.shouldUseColors
  }

  public init(colorMode: ColorMode = .auto) {
    self.colorMode = colorMode
  }

  /// Apply color to text if colors are enabled
  private func color(_ text: String, _ colorCode: String) -> String {
    guard useColors else { return text }
    return "\(colorCode)\(text)\(ANSIColors.reset)"
  }

  /// Format a full binary analysis
  public func format(_ binary: MachOBinary, options: FormatOptions = FormatOptions()) -> String {
    var output: [String] = []

    // Header
    output.append(color("=== Mach-O Binary Analysis ===", ANSIColors.header))
    output.append("File: \(binary.path)")
    output.append("Size: \(formatSize(binary.fileSize))")
    output.append("")

    // Mach Header
    if options.showHeaders {
      output.append(formatHeader(binary.header))
      output.append("")
    }

    // Load Commands Summary
    if options.showLoadCommands {
      output.append(formatLoadCommandsSummary(binary.loadCommands))
      output.append("")
    }

    // Segments and Sections
    if options.showSegments {
      output.append(formatSegments(binary.segments))
      output.append("")
    }

    // Symbols
    if options.showSymbols {
      if let symbols = binary.symbols {
        output.append(formatSymbols(symbols))
        output.append("")
      }
    }

    // Dylibs
    if options.showDylibs {
      let dylibs = binary.dylibDependencies
      if !dylibs.isEmpty {
        output.append(formatDylibs(dylibs))
        output.append("")
      }
    }

    // Strings
    if options.showStrings {
      let extractor = StringExtractor(binary: binary)
      if let strings = try? extractor.extractAllStrings() {
        output.append(formatStrings(strings))
        output.append("")
      }
    }

    // Code Signature
    if options.showSignature || options.showEntitlements {
      if let codeSignature = try? binary.parseCodeSignature() {
        if options.showSignature {
          output.append(formatCodeSignature(codeSignature))
          output.append("")
        }

        // Entitlements (only if showEntitlements or shown as part of signature)
        if options.showEntitlements {
          if let entitlements = codeSignature.entitlements, !entitlements.isEmpty {
            output.append(formatEntitlements(entitlements))
            output.append("")
          }
        }
      } else if options.showSignature {
        output.append("--- Code Signature ---")
        output.append("  Not signed")
        output.append("")
      }
    }

    return output.joined(separator: "\n")
  }

  /// Format the Mach-O header
  public func formatHeader(_ header: MachHeader) -> String {
    var lines: [String] = []
    lines.append(color("--- Mach Header ---", ANSIColors.subheader))
    lines.append("  Magic:        \(String(format: "0x%08X", header.magic))")
    lines.append("  CPU Type:     \(header.cpuType)")
    lines.append("  CPU Subtype:  \(header.cpuSubtype)")
    lines.append("  File Type:    \(header.fileType.displayName)")
    lines.append("  Load Cmds:    \(header.numberOfCommands)")
    lines.append("  Cmds Size:    \(header.sizeOfCommands) bytes")
    lines.append("  Flags:        \(header.flags.flagNames.joined(separator: " "))")
    return lines.joined(separator: "\n")
  }

  /// Format load commands summary
  public func formatLoadCommandsSummary(_ commands: [LoadCommand]) -> String {
    var lines: [String] = []
    lines.append(color("--- Load Commands (\(commands.count)) ---", ANSIColors.subheader))

    // Group by type
    var typeCounts: [String: Int] = [:]
    for cmd in commands {
      let name = cmd.type?.description ?? "UNKNOWN(0x\(String(format: "%X", cmd.rawType)))"
      typeCounts[name, default: 0] += 1
    }

    for (name, count) in typeCounts.sorted(by: { $0.key < $1.key }) {
      lines.append("  \(name): \(count)")
    }

    return lines.joined(separator: "\n")
  }

  /// Format segments and their sections
  public func formatSegments(_ segments: [Segment]) -> String {
    var lines: [String] = []
    lines.append(color("--- Segments (\(segments.count)) ---", ANSIColors.subheader))

    for segment in segments {
      lines.append("  \(color(segment.name, ANSIColors.bold))")
      lines.append(
        "    VM Address:  \(color(String(format: "0x%016llX", segment.vmAddress), ANSIColors.address))"
      )
      lines.append("    VM Size:     \(formatSize(segment.vmSize))")
      lines.append("    File Size:   \(formatSize(segment.fileSize))")
      lines.append("    Protection:  \(segment.initialProtection)")

      if !segment.sections.isEmpty {
        lines.append("    Sections (\(segment.sections.count)):")
        for section in segment.sections {
          lines.append("      \(color(section.name, ANSIColors.info))")
          lines.append(
            "        Address: \(color(String(format: "0x%016llX", section.address), ANSIColors.address))"
          )
          lines.append("        Size:    \(formatSize(section.size))")
          lines.append(
            "        Type:    \(color(String(describing: section.type), ANSIColors.dim))")
        }
      }
    }

    return lines.joined(separator: "\n")
  }

  /// Format symbol table
  public func formatSymbols(_ symbols: [Symbol], limit: Int = 50) -> String {
    var lines: [String] = []

    let defined = symbols.filter { $0.isDefined && !$0.isDebugSymbol }
    let undefined = symbols.filter { !$0.isDefined && !$0.isDebugSymbol }

    lines.append(color("--- Symbols ---", ANSIColors.subheader))
    lines.append(
      "  Total: \(symbols.count) (defined: \(defined.count), undefined: \(undefined.count))")

    // Show first N defined symbols
    let displaySymbols = Array(defined.prefix(limit))
    if !displaySymbols.isEmpty {
      lines.append("")
      lines.append("  Defined symbols (first \(displaySymbols.count)):")
      for symbol in displaySymbols {
        let addr = color(String(format: "0x%016llX", symbol.address), ANSIColors.address)
        let type = symbol.isExternal ? "T" : "t"
        let name = color(symbol.name, ANSIColors.symbol)
        lines.append("    \(addr) \(type) \(name)")
      }
    }

    if defined.count > limit {
      lines.append("    ... and \(defined.count - limit) more")
    }

    return lines.joined(separator: "\n")
  }

  /// Format dylib dependencies
  public func formatDylibs(_ dylibs: [DylibCommand]) -> String {
    var lines: [String] = []
    lines.append(color("--- Dynamic Libraries (\(dylibs.count)) ---", ANSIColors.subheader))

    for dylib in dylibs {
      lines.append("  \(color(dylib.name, ANSIColors.info))")
      lines.append("    Version: \(color(dylib.currentVersionString, ANSIColors.dim))")
    }

    return lines.joined(separator: "\n")
  }

  /// Format extracted strings
  public func formatStrings(_ strings: [ExtractedString], limit: Int = 100) -> String {
    var lines: [String] = []

    // Group by section
    let grouped = Dictionary(grouping: strings) { $0.section }

    lines.append(color("--- Strings ---", ANSIColors.subheader))
    lines.append("  Total: \(strings.count) strings across \(grouped.count) sections")

    for (section, sectionStrings) in grouped.sorted(by: { $0.key < $1.key }) {
      lines.append("")
      lines.append(
        "  Section: \(color(section, ANSIColors.info)) (\(sectionStrings.count) strings)")

      let displayStrings = Array(sectionStrings.prefix(limit))
      for string in displayStrings {
        let offsetStr = color(String(format: "0x%08X", string.offset), ANSIColors.address)
        // Escape special characters for display
        let escaped = escapeString(string.value)
        lines.append("    \(offsetStr): \"\(escaped)\"")
      }

      if sectionStrings.count > limit {
        lines.append("    ... and \(sectionStrings.count - limit) more")
      }
    }

    return lines.joined(separator: "\n")
  }

  /// Escape special characters in a string for display
  private func escapeString(_ string: String) -> String {
    var result = ""
    for char in string {
      switch char {
      case "\n": result += "\\n"
      case "\r": result += "\\r"
      case "\t": result += "\\t"
      case "\\": result += "\\\\"
      case "\"": result += "\\\""
      default: result.append(char)
      }
    }
    // Truncate long strings
    if result.count > 80 {
      return String(result.prefix(77)) + "..."
    }
    return result
  }

  /// Format a byte size
  private func formatSize(_ bytes: UInt64) -> String {
    if bytes >= 1024 * 1024 {
      return String(format: "%.2f MB", Double(bytes) / (1024 * 1024))
    } else if bytes >= 1024 {
      return String(format: "%.2f KB", Double(bytes) / 1024)
    } else {
      return "\(bytes) bytes"
    }
  }

  /// Format code signature information
  public func formatCodeSignature(_ signature: CodeSignature) -> String {
    var lines: [String] = []
    lines.append(color("--- Code Signature ---", ANSIColors.subheader))

    if let cd = signature.codeDirectory {
      lines.append("  Identifier:   \(cd.identifier)")
      if let teamID = cd.teamID {
        lines.append("  Team ID:      \(teamID)")
      }
      lines.append("  Flags:        \(cd.flags.flagNames.joined(separator: ", "))")
      lines.append("  Hash Type:    \(cd.hashType)")
      lines.append("  Page Size:    \(cd.pageSizeBytes) bytes")
      lines.append("  Code Limit:   \(cd.codeLimit) bytes")
      if let cdHash = cd.cdHashString {
        lines.append("  CDHash:       \(cdHash)")
      }
      lines.append("  Code Slots:   \(cd.codeSlotCount)")
      lines.append("  Special Slots: \(cd.specialSlotCount)")

      // Signature type
      if cd.isLinkerSigned {
        lines.append("  Signature:    Linker-signed (ad-hoc)")
      } else if cd.isAdhoc {
        lines.append("  Signature:    Ad-hoc (no certificate)")
      } else {
        lines.append("  Signature:    Signed with certificate")
      }

      if cd.hasHardenedRuntime {
        lines.append("  Runtime:      Hardened")
      }
    }

    // SuperBlob summary
    lines.append("")
    lines.append("  Blobs: \(signature.superBlob.blobCount)")
    for blob in signature.superBlob.blobs {
      let slotName = blob.slot?.description ?? "Unknown(\(blob.rawSlot))"
      lines.append("    - \(slotName): \(blob.length) bytes")
    }

    return lines.joined(separator: "\n")
  }

  /// Format entitlements
  public func formatEntitlements(_ entitlements: Entitlements) -> String {
    var lines: [String] = []
    lines.append(
      color(
        "--- Entitlements (\(entitlements.format), \(entitlements.count) entries) ---",
        ANSIColors.subheader))

    for key in entitlements.keys {
      let value = formatEntitlementValue(entitlements.entries[key])
      lines.append("  \(key): \(value)")
    }

    return lines.joined(separator: "\n")
  }

  /// Format an entitlement value
  private func formatEntitlementValue(_ value: Any?) -> String {
    switch value {
    case let bool as Bool:
      return bool ? "true" : "false"
    case let string as String:
      return "\"\(string)\""
    case let array as [Any]:
      if array.isEmpty {
        return "[]"
      } else if let strings = array as? [String], strings.count <= 3 {
        return "[\(strings.map { "\"\($0)\"" }.joined(separator: ", "))]"
      } else {
        return "[\(array.count) items]"
      }
    case let dict as [String: Any]:
      return "{\(dict.count) keys}"
    case let number as NSNumber:
      return number.stringValue
    default:
      return String(describing: value ?? "nil")
    }
  }
}

/// Formatting options
public struct FormatOptions: Sendable {
  public var showHeaders: Bool = true
  public var showLoadCommands: Bool = true
  public var showSegments: Bool = true
  public var showSymbols: Bool = true
  public var showDylibs: Bool = true
  public var showStrings: Bool = false
  public var showSignature: Bool = false
  public var showEntitlements: Bool = false

  public init(
    showHeaders: Bool = true,
    showLoadCommands: Bool = true,
    showSegments: Bool = true,
    showSymbols: Bool = true,
    showDylibs: Bool = true,
    showStrings: Bool = false,
    showSignature: Bool = false,
    showEntitlements: Bool = false
  ) {
    self.showHeaders = showHeaders
    self.showLoadCommands = showLoadCommands
    self.showSegments = showSegments
    self.showSymbols = showSymbols
    self.showDylibs = showDylibs
    self.showStrings = showStrings
    self.showSignature = showSignature
    self.showEntitlements = showEntitlements
  }
}
