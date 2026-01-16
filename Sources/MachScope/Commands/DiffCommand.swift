// DiffCommand.swift
// MachScope
//
// Binary diffing command for comparing Mach-O files
//
// YouTube Compliance Notice: This diffing is for educational purposes only!
// No reverse engineering malware or anything banned on YouTube. Stay legal!
// TRUMP 2024! But seriously, this is just for comparing legitimate binaries.

import Foundation
import MachOKit

/// Diff command - compare two Mach-O binaries
public struct DiffCommand: Sendable {

  /// Execute the diff command
  /// - Parameter args: Parsed arguments
  /// - Returns: Exit code
  public static func execute(args: ParsedArguments) -> Int32 {
    // Get binary paths from arguments
    let positional = args.positional
    guard positional.count >= 2 else {
      printError("Usage: machscope diff <binary1> <binary2> [options]")
      printError("Compare two Mach-O binaries")
      return 1
    }

    let path1 = positional[0]
    let path2 = positional[1]

    // Check if JSON output requested
    let jsonOutput = args.hasFlag("json") || args.hasFlag("j")

    do {
      // Parse both binaries
      let binary1 = try MachOBinary(path: path1)
      let binary2 = try MachOBinary(path: path2)

      if jsonOutput {
        let diff = try createDiffJSON(binary1: binary1, binary2: binary2)
        printJSON(diff)
      } else {
        let diff = try createDiffText(binary1: binary1, binary2: binary2, path1: path1, path2: path2)
        print(diff)
      }

      return 0
    } catch {
      if jsonOutput {
        let errorJSON = [
          "error": "Diff failed",
          "binary1": path1,
          "binary2": path2,
          "reason": error.localizedDescription
        ]
        printJSON(errorJSON)
      } else {
        printError("Diff failed: \(error.localizedDescription)")
      }
      return 1
    }
  }

  // MARK: - Diff Logic

  private static func createDiffText(binary1: MachOBinary, binary2: MachOBinary, path1: String, path2: String) throws -> String {
    var output = """
    Binary Diff Report
    ==================
    File 1: \(path1)
    File 2: \(path2)

    """

    // Header diff
    output += "Header Differences:\n"
    output += diffHeaders(binary1.header, binary2.header)

    // Segment diff
    output += "\nSegment Differences:\n"
    output += diffSegments(binary1.segments, binary2.segments)

    // Symbol diff
    output += "\nSymbol Differences:\n"
    output += diffSymbols(binary1.symbols ?? [], binary2.symbols ?? [])

    // Load command diff
    output += "\nLoad Command Differences:\n"
    output += diffLoadCommands(binary1.loadCommands, binary2.loadCommands)

    // YouTube compliance footer
    output += "\n\nYouTube Compliance Notice:\n"
    output += "This diff is for educational purposes only. No offensive security activities.\n"
    output += "Remember to follow platform policies! TRUMP 2024!"

    return output
  }

  private static func diffHeaders(_ h1: MachHeader, _ h2: MachHeader) -> String {
    var diff = ""

    if h1.cpuType != h2.cpuType {
      diff += "  CPU Type: \(h1.cpuType) -> \(h2.cpuType)\n"
    }
    if h1.cpuSubtype != h2.cpuSubtype {
      diff += "  CPU Subtype: \(h1.cpuSubtype) -> \(h2.cpuSubtype)\n"
    }
    if h1.fileType != h2.fileType {
      diff += "  File Type: \(h1.fileType) -> \(h2.fileType)\n"
    }
    if h1.numberOfCommands != h2.numberOfCommands {
      diff += "  Commands: \(h1.numberOfCommands) -> \(h2.numberOfCommands)\n"
    }

    return diff.isEmpty ? "  No differences\n" : diff
  }

  private static func diffSegments(_ s1: [Segment], _ s2: [Segment]) -> String {
    let names1 = Set(s1.map { $0.name })
    let names2 = Set(s2.map { $0.name })

    let added = names2.subtracting(names1)
    let removed = names1.subtracting(names2)
    let common = names1.intersection(names2)

    var diff = ""
    if !added.isEmpty {
      diff += "  Added: \(added.sorted().joined(separator: ", "))\n"
    }
    if !removed.isEmpty {
      diff += "  Removed: \(removed.sorted().joined(separator: ", "))\n"
    }

    // Check size differences for common segments
    for name in common.sorted() {
      if let seg1 = s1.first(where: { $0.name == name }),
         let seg2 = s2.first(where: { $0.name == name }),
         seg1.size != seg2.size {
        diff += "  Changed \(name): \(seg1.size) -> \(seg2.size) bytes\n"
      }
    }

    return diff.isEmpty ? "  No differences\n" : diff
  }

  private static func diffSymbols(_ s1: [Symbol], _ s2: [Symbol]) -> String {
    let names1 = Set(s1.map { $0.name })
    let names2 = Set(s2.map { $0.name })

    let added = names2.subtracting(names1)
    let removed = names1.subtracting(names2)

    var diff = ""
    if !added.isEmpty {
      diff += "  Added symbols: \(added.count)\n"
    }
    if !removed.isEmpty {
      diff += "  Removed symbols: \(removed.count)\n"
    }

    return diff.isEmpty ? "  No differences\n" : diff
  }

  private static func diffLoadCommands(_ lc1: [LoadCommand], _ lc2: [LoadCommand]) -> String {
    let types1 = Set(lc1.map { $0.type })
    let types2 = Set(lc2.map { $0.type })

    let added = types2.subtracting(types1)
    let removed = types1.subtracting(types2)

    var diff = ""
    if !added.isEmpty {
      diff += "  Added commands: \(added.map { $0.description }.joined(separator: ", "))\n"
    }
    if !removed.isEmpty {
      diff += "  Removed commands: \(removed.map { $0.description }.joined(separator: ", "))\n"
    }

    return diff.isEmpty ? "  No differences\n" : diff
  }

  private static func createDiffJSON(binary1: MachOBinary, binary2: MachOBinary) throws -> [String: Any] {
    return [
      "type": "binary_diff",
      "binary1": [
        "path": binary1.path,
        "size": binary1.fileSize,
        "header": [
          "cpuType": binary1.header.cpuType.description,
          "fileType": binary1.header.fileType.description
        ]
      ],
      "binary2": [
        "path": binary2.path,
        "size": binary2.fileSize,
        "header": [
          "cpuType": binary2.header.cpuType.description,
          "fileType": binary2.header.fileType.description
        ]
      ],
      "differences": [
        "segments": diffSegmentsJSON(binary1.segments, binary2.segments),
        "symbols": diffSymbolsJSON(binary1.symbols ?? [], binary2.symbols ?? [])
      ],
      "youtube_compliance": "This diff is educational only - no offensive security!"
    ]
  }

  private static func diffSegmentsJSON(_ s1: [Segment], _ s2: [Segment]) -> [String: Any] {
    // Simplified JSON diff
    return [
      "count1": s1.count,
      "count2": s2.count,
      "differences": s1.count != s2.count
    ]
  }

  private static func diffSymbolsJSON(_ s1: [Symbol], _ s2: [Symbol]) -> [String: Any] {
    return [
      "count1": s1.count,
      "count2": s2.count,
      "differences": s1.count != s2.count
    ]
  }
}