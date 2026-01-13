// JSONFormatter.swift
// MachScope
//
// JSON output formatter

import Foundation
import MachOKit

/// JSON formatter for machine-readable output
public struct JSONFormatter: Sendable {

  public init() {}

  /// Format a full binary analysis as JSON
  public func format(_ binary: MachOBinary, options: FormatOptions = FormatOptions()) -> String {
    var dict: [String: Any] = [:]

    dict["path"] = binary.path
    dict["fileSize"] = binary.fileSize
    dict["isMemoryMapped"] = binary.isMemoryMapped

    // Header
    if options.showHeaders {
      dict["header"] = formatHeader(binary.header)
    }

    // UUID
    if let uuid = binary.uuid {
      dict["uuid"] = uuid.uuidString
    }

    // Build Version
    if let buildVersion = binary.buildVersion {
      dict["buildVersion"] = [
        "platform": buildVersion.platform,
        "minOS": buildVersion.minOS,
        "sdk": buildVersion.sdk,
      ]
    }

    // Entry Point
    if let entryPoint = binary.entryPoint {
      dict["entryPoint"] = [
        "offset": entryPoint.entryOffset,
        "stackSize": entryPoint.stackSize,
      ]
    }

    // Segments
    if options.showSegments {
      dict["segments"] = binary.segments.map { formatSegment($0) }
    }

    // Symbols
    if options.showSymbols, let symbols = binary.symbols {
      let filtered = symbols.filter { !$0.isDebugSymbol }
      let limit = options.limit ?? 100
      let entries: [[String: Any]]
      if limit == 0 {
        entries = filtered.map { formatSymbol($0) }
      } else {
        entries = filtered.prefix(limit).map { formatSymbol($0) }
      }
      dict["symbols"] = [
        "total": symbols.count,
        "defined": filtered.filter { $0.isDefined }.count,
        "undefined": filtered.filter { !$0.isDefined }.count,
        "entries": entries,
        "limited": limit > 0 && filtered.count > limit,
      ]
    }

    // Dylibs
    if options.showDylibs {
      let dylibs = binary.dylibDependencies
      dict["dylibs"] = dylibs.map { formatDylib($0) }
    }

    // Load Commands Summary
    if options.showLoadCommands {
      var cmdCounts: [String: Int] = [:]
      for cmd in binary.loadCommands {
        let name = cmd.type?.description ?? "UNKNOWN"
        cmdCounts[name, default: 0] += 1
      }
      dict["loadCommands"] = [
        "total": binary.loadCommands.count,
        "types": cmdCounts,
      ]
    }

    // Strings
    if options.showStrings {
      let extractor = StringExtractor(binary: binary)
      if let strings = try? extractor.extractAllStrings() {
        // Group by section for better organization
        let grouped = Dictionary(grouping: strings) { $0.section }
        var sectionData: [[String: Any]] = []
        let limit = options.limit ?? 100

        for (section, sectionStrings) in grouped.sorted(by: { $0.key < $1.key }) {
          let entries: [[String: Any]]
          if limit == 0 {
            entries = sectionStrings.map { formatExtractedString($0) }
          } else {
            entries = sectionStrings.prefix(limit).map { formatExtractedString($0) }
          }
          sectionData.append([
            "section": section,
            "count": sectionStrings.count,
            "entries": entries,
            "limited": limit > 0 && sectionStrings.count > limit,
          ])
        }

        dict["strings"] = [
          "total": strings.count,
          "sections": sectionData,
        ]
      }
    }

    // Code Signature
    if options.showSignature || options.showEntitlements {
      if let codeSignature = try? binary.parseCodeSignature() {
        if options.showSignature {
          dict["codeSignature"] = formatCodeSignature(codeSignature)
        }

        if options.showEntitlements {
          if let entitlements = codeSignature.entitlements {
            dict["entitlements"] = formatEntitlements(entitlements)
          }
        }
      } else if options.showSignature {
        dict["codeSignature"] = ["signed": false]
      }
    }

    return toJSON(dict)
  }

  /// Format header as dictionary
  private func formatHeader(_ header: MachHeader) -> [String: Any] {
    [
      "magic": String(format: "0x%08X", header.magic),
      "cpuType": header.cpuType.description,
      "cpuSubtype": header.cpuSubtype.description,
      "fileType": header.fileType.description,
      "numberOfCommands": header.numberOfCommands,
      "sizeOfCommands": header.sizeOfCommands,
      "flags": header.flags.flagNames,
    ]
  }

  /// Format segment as dictionary
  private func formatSegment(_ segment: Segment) -> [String: Any] {
    [
      "name": segment.name,
      "vmAddress": String(format: "0x%llX", segment.vmAddress),
      "vmSize": segment.vmSize,
      "fileOffset": segment.fileOffset,
      "fileSize": segment.fileSize,
      "protection": segment.initialProtection.description,
      "sections": segment.sections.map { formatSection($0) },
    ]
  }

  /// Format section as dictionary
  private func formatSection(_ section: Section) -> [String: Any] {
    [
      "name": section.name,
      "segmentName": section.segmentName,
      "address": String(format: "0x%llX", section.address),
      "size": section.size,
      "offset": section.offset,
      "type": section.type.description,
    ]
  }

  /// Format symbol as dictionary
  private func formatSymbol(_ symbol: Symbol) -> [String: Any] {
    [
      "name": symbol.name,
      "address": String(format: "0x%llX", symbol.address),
      "type": symbol.type.description,
      "external": symbol.isExternal,
      "defined": symbol.isDefined,
    ]
  }

  /// Format dylib as dictionary
  private func formatDylib(_ dylib: DylibCommand) -> [String: Any] {
    [
      "name": dylib.name,
      "currentVersion": dylib.currentVersionString,
      "compatibilityVersion": dylib.compatibilityVersionString,
    ]
  }

  /// Format extracted string as dictionary
  private func formatExtractedString(_ string: ExtractedString) -> [String: Any] {
    var result: [String: Any] = [
      "value": string.value,
      "offset": string.offset,
    ]
    if let address = string.address {
      result["address"] = String(format: "0x%llX", address)
    }
    return result
  }

  /// Format code signature as dictionary
  private func formatCodeSignature(_ signature: CodeSignature) -> [String: Any] {
    var result: [String: Any] = [
      "signed": true,
      "blobCount": signature.superBlob.blobCount,
    ]

    if let cd = signature.codeDirectory {
      result["identifier"] = cd.identifier
      if let teamID = cd.teamID {
        result["teamID"] = teamID
      }
      result["flags"] = cd.flags.flagNames
      result["hashType"] = cd.hashType.description
      result["pageSize"] = cd.pageSizeBytes
      result["codeLimit"] = cd.codeLimit
      result["codeSlots"] = cd.codeSlotCount
      result["specialSlots"] = cd.specialSlotCount
      result["adhoc"] = cd.isAdhoc
      result["linkerSigned"] = cd.isLinkerSigned
      result["hardenedRuntime"] = cd.hasHardenedRuntime

      if let cdHash = cd.cdHashString {
        result["cdHash"] = cdHash
      }

      result["version"] = cd.versionString
    }

    // Blobs summary
    var blobs: [[String: Any]] = []
    for blob in signature.superBlob.blobs {
      blobs.append([
        "slot": blob.slot?.description ?? "Unknown(\(blob.rawSlot))",
        "length": blob.length,
        "magic": blob.magicType?.description ?? String(format: "0x%08X", blob.magic),
      ])
    }
    result["blobs"] = blobs

    return result
  }

  /// Format entitlements as dictionary
  private func formatEntitlements(_ entitlements: Entitlements) -> [String: Any] {
    var result: [String: Any] = [
      "format": entitlements.format.description,
      "count": entitlements.count,
    ]

    // Include all entries - plist types serialize naturally to JSON
    var entries: [String: Any] = [:]
    for key in entitlements.keys {
      entries[key] = entitlements.entries[key]
    }
    result["entries"] = entries

    // Include raw XML if available
    if let rawXML = entitlements.rawXML {
      result["rawXML"] = rawXML
    }

    return result
  }

  /// Convert dictionary to pretty-printed JSON
  private func toJSON(_ dict: [String: Any]) -> String {
    do {
      let data = try JSONSerialization.data(
        withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
      return String(data: data, encoding: .utf8) ?? "{}"
    } catch {
      return "{\"error\": \"Failed to serialize JSON\"}"
    }
  }
}
