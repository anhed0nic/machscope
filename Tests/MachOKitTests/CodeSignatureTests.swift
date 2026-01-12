// CodeSignatureTests.swift
// MachOKitTests
//
// Tests for code signature parsing (SuperBlob, CodeDirectory)

import XCTest

@testable import MachOKit

final class CodeSignatureTests: XCTestCase {

  // MARK: - Test Fixtures

  /// Path to the simple_arm64 fixture (should be ad-hoc signed)
  var simpleARM64Path: String {
    let bundle = Bundle(for: type(of: self))
    if let path = bundle.path(forResource: "simple_arm64", ofType: nil) {
      return path
    }
    // Fallback to relative path for SPM tests
    return "Tests/MachOKitTests/Fixtures/simple_arm64"
  }

  /// Path to the fat binary fixture
  var fatBinaryPath: String {
    let bundle = Bundle(for: type(of: self))
    if let path = bundle.path(forResource: "fat_binary", ofType: nil) {
      return path
    }
    return "Tests/MachOKitTests/Fixtures/fat_binary"
  }

  // MARK: - SuperBlob Magic Tests

  func testCodeSignatureMagicValues() {
    // Verify magic constants match Apple's definitions
    XCTAssertEqual(CodeSignatureMagic.superBlob.rawValue, 0xFADE_0CC0)
    XCTAssertEqual(CodeSignatureMagic.codeDirectory.rawValue, 0xFADE_0C02)
    XCTAssertEqual(CodeSignatureMagic.requirements.rawValue, 0xFADE_0C01)
    XCTAssertEqual(CodeSignatureMagic.entitlements.rawValue, 0xFADE_7171)
    XCTAssertEqual(CodeSignatureMagic.entitlementsDER.rawValue, 0xFADE_7172)
    XCTAssertEqual(CodeSignatureMagic.cmsSignature.rawValue, 0xFADE_0B01)
  }

  func testCodeSignatureSlotValues() {
    // Verify slot constants
    XCTAssertEqual(CodeSignatureSlot.codeDirectory.rawValue, 0)
    XCTAssertEqual(CodeSignatureSlot.requirements.rawValue, 2)
    XCTAssertEqual(CodeSignatureSlot.entitlements.rawValue, 5)
    XCTAssertEqual(CodeSignatureSlot.entitlementsDER.rawValue, 7)
    XCTAssertEqual(CodeSignatureSlot.cmsSignature.rawValue, 0x10000)
  }

  // MARK: - SuperBlob Parsing Tests

  func testSuperBlobParsing() throws {
    // Create a minimal SuperBlob for testing
    // SuperBlob header: magic (4), length (4), count (4) = 12 bytes
    // BlobIndex: type (4), offset (4) = 8 bytes per entry

    var data = Data()

    // SuperBlob header (big-endian)
    data.append(contentsOf: withUnsafeBytes(of: UInt32(0xFADE_0CC0).bigEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt32(36).bigEndian) { Array($0) })  // length
    data.append(contentsOf: withUnsafeBytes(of: UInt32(1).bigEndian) { Array($0) })  // count

    // BlobIndex for CodeDirectory
    data.append(contentsOf: withUnsafeBytes(of: UInt32(0).bigEndian) { Array($0) })  // slot = codeDirectory
    data.append(contentsOf: withUnsafeBytes(of: UInt32(20).bigEndian) { Array($0) })  // offset

    // Minimal blob header at offset 20
    data.append(contentsOf: withUnsafeBytes(of: UInt32(0xFADE_0C02).bigEndian) { Array($0) })  // magic
    data.append(contentsOf: withUnsafeBytes(of: UInt32(16).bigEndian) { Array($0) })  // length

    // 8 bytes of padding (blob data)
    data.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0])

    let reader = BinaryReader(data: data)
    let superBlob = try SuperBlob.parse(from: reader)

    XCTAssertEqual(superBlob.magic, 0xFADE_0CC0)
    XCTAssertEqual(superBlob.blobCount, 1)
    XCTAssertEqual(superBlob.blobs.count, 1)
    XCTAssertEqual(superBlob.blobs[0].slot, .codeDirectory)
    XCTAssertEqual(superBlob.blobs[0].magic, 0xFADE_0C02)
  }

  func testSuperBlobInvalidMagic() {
    var data = Data()
    // Invalid magic
    data.append(contentsOf: withUnsafeBytes(of: UInt32(0xDEAD_BEEF).bigEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt32(12).bigEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt32(0).bigEndian) { Array($0) })

    let reader = BinaryReader(data: data)

    XCTAssertThrowsError(try SuperBlob.parse(from: reader)) { error in
      guard case MachOParseError.invalidCodeSignatureMagic = error else {
        XCTFail("Expected invalidCodeSignatureMagic error")
        return
      }
    }
  }

  func testSuperBlobBlobLookup() throws {
    // Create a SuperBlob with multiple blobs
    var data = Data()

    // Header
    data.append(contentsOf: withUnsafeBytes(of: UInt32(0xFADE_0CC0).bigEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt32(60).bigEndian) { Array($0) })  // length
    data.append(contentsOf: withUnsafeBytes(of: UInt32(2).bigEndian) { Array($0) })  // count

    // BlobIndex 0: CodeDirectory at offset 28
    data.append(contentsOf: withUnsafeBytes(of: UInt32(0).bigEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt32(28).bigEndian) { Array($0) })

    // BlobIndex 1: Requirements at offset 44
    data.append(contentsOf: withUnsafeBytes(of: UInt32(2).bigEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt32(44).bigEndian) { Array($0) })

    // CodeDirectory blob at offset 28
    data.append(contentsOf: withUnsafeBytes(of: UInt32(0xFADE_0C02).bigEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt32(16).bigEndian) { Array($0) })
    data.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0])

    // Requirements blob at offset 44
    data.append(contentsOf: withUnsafeBytes(of: UInt32(0xFADE_0C01).bigEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt32(16).bigEndian) { Array($0) })
    data.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0])

    let reader = BinaryReader(data: data)
    let superBlob = try SuperBlob.parse(from: reader)

    XCTAssertEqual(superBlob.blobCount, 2)
    XCTAssertNotNil(superBlob.codeDirectoryBlob)
    XCTAssertNotNil(superBlob.requirementsBlob)
    XCTAssertNil(superBlob.entitlementsBlob)
  }

  // MARK: - CodeDirectory Tests

  func testHashTypeValues() {
    XCTAssertEqual(HashType.sha1.rawValue, 1)
    XCTAssertEqual(HashType.sha256.rawValue, 2)
    XCTAssertEqual(HashType.sha384.rawValue, 4)

    XCTAssertEqual(HashType.sha1.digestSize, 20)
    XCTAssertEqual(HashType.sha256.digestSize, 32)
    XCTAssertEqual(HashType.sha384.digestSize, 48)
  }

  func testCodeDirectoryFlags() {
    let flags: CodeDirectoryFlags = [.adhoc, .linkerSigned]

    XCTAssertTrue(flags.contains(.adhoc))
    XCTAssertTrue(flags.contains(.linkerSigned))
    XCTAssertFalse(flags.contains(.runtime))

    let names = flags.flagNames
    XCTAssertTrue(names.contains("adhoc"))
    XCTAssertTrue(names.contains("linker-signed"))
  }

  // MARK: - Integration Tests with Real Binaries

  func testParseCodeSignatureFromSimpleARM64() throws {
    // Skip if fixture doesn't exist
    guard FileManager.default.fileExists(atPath: simpleARM64Path) else {
      throw XCTSkip("Test fixture not found at \(simpleARM64Path)")
    }

    let binary = try MachOBinary(path: simpleARM64Path)

    // The binary should be signed (at least ad-hoc)
    XCTAssertTrue(binary.isSigned)

    // Parse the code signature
    let codeSignature = try binary.parseCodeSignature()
    XCTAssertNotNil(codeSignature)

    // Verify CodeDirectory was parsed
    let cd = codeSignature?.codeDirectory
    XCTAssertNotNil(cd)

    // Ad-hoc or linker-signed binaries should have the adhoc or linkerSigned flag
    let isAdhocOrLinkerSigned = cd?.isAdhoc == true || cd?.isLinkerSigned == true
    XCTAssertTrue(isAdhocOrLinkerSigned, "Expected ad-hoc or linker-signed binary")

    // Should have an identifier
    XCTAssertNotNil(cd?.identifier)
    XCTAssertFalse(cd?.identifier.isEmpty ?? true)

    // Should have hash type
    XCTAssertNotNil(cd?.hashType)

    // CDHash should be computed
    XCTAssertNotNil(cd?.cdHashString)
  }

  func testParseCodeSignatureFromFatBinary() throws {
    // Skip if fixture doesn't exist
    guard FileManager.default.fileExists(atPath: fatBinaryPath) else {
      throw XCTSkip("Test fixture not found at \(fatBinaryPath)")
    }

    let binary = try MachOBinary(path: fatBinaryPath, architecture: .arm64)

    // Parse the code signature
    if binary.isSigned {
      let codeSignature = try binary.parseCodeSignature()
      XCTAssertNotNil(codeSignature)

      // SuperBlob should have at least CodeDirectory
      XCTAssertNotNil(codeSignature?.superBlob.codeDirectoryBlob)
    }
  }

  // MARK: - Binary with No Signature

  func testBinaryWithNoCodeSignature() throws {
    // Create a minimal Mach-O without code signature
    var data = Data()

    // Mach-O 64-bit header
    data.append(contentsOf: withUnsafeBytes(of: UInt32(0xFEED_FACF)) { Array($0) })  // magic
    data.append(contentsOf: withUnsafeBytes(of: UInt32(0x0100_000C)) { Array($0) })  // CPU_TYPE_ARM64
    data.append(contentsOf: withUnsafeBytes(of: UInt32(0)) { Array($0) })  // cpu subtype
    data.append(contentsOf: withUnsafeBytes(of: UInt32(2)) { Array($0) })  // MH_EXECUTE
    data.append(contentsOf: withUnsafeBytes(of: UInt32(0)) { Array($0) })  // ncmds = 0
    data.append(contentsOf: withUnsafeBytes(of: UInt32(0)) { Array($0) })  // sizeofcmds
    data.append(contentsOf: withUnsafeBytes(of: UInt32(0)) { Array($0) })  // flags
    data.append(contentsOf: withUnsafeBytes(of: UInt32(0)) { Array($0) })  // reserved

    // Write to temp file
    let tempPath = NSTemporaryDirectory() + "test_unsigned_\(UUID().uuidString)"
    try data.write(to: URL(fileURLWithPath: tempPath))
    defer { try? FileManager.default.removeItem(atPath: tempPath) }

    let binary = try MachOBinary(path: tempPath)

    XCTAssertFalse(binary.isSigned)
    XCTAssertNil(binary.codeSignatureInfo)

    let codeSignature = try binary.parseCodeSignature()
    XCTAssertNil(codeSignature)
  }

  // MARK: - Description Tests

  func testSuperBlobDescription() throws {
    var data = Data()

    // Header
    data.append(contentsOf: withUnsafeBytes(of: UInt32(0xFADE_0CC0).bigEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt32(36).bigEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt32(1).bigEndian) { Array($0) })

    // BlobIndex
    data.append(contentsOf: withUnsafeBytes(of: UInt32(0).bigEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt32(20).bigEndian) { Array($0) })

    // Blob
    data.append(contentsOf: withUnsafeBytes(of: UInt32(0xFADE_0C02).bigEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt32(16).bigEndian) { Array($0) })
    data.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0])

    let reader = BinaryReader(data: data)
    let superBlob = try SuperBlob.parse(from: reader)

    let description = superBlob.description
    XCTAssertTrue(description.contains("SuperBlob"))
    XCTAssertTrue(description.contains("36 bytes"))
    XCTAssertTrue(description.contains("1"))
  }

  func testCodeDirectoryFlagsDescription() {
    let emptyFlags = CodeDirectoryFlags([])
    XCTAssertEqual(emptyFlags.flagNames, ["none"])

    let multipleFlags: CodeDirectoryFlags = [.adhoc, .runtime]
    let names = multipleFlags.flagNames
    XCTAssertTrue(names.contains("adhoc"))
    XCTAssertTrue(names.contains("runtime"))
  }
}

// MARK: - Performance Tests

extension CodeSignatureTests {
  func testCodeSignatureParsingPerformance() throws {
    guard FileManager.default.fileExists(atPath: simpleARM64Path) else {
      throw XCTSkip("Test fixture not found")
    }

    let binary = try MachOBinary(path: simpleARM64Path)
    guard binary.isSigned else {
      throw XCTSkip("Binary is not signed")
    }

    measure {
      do {
        _ = try binary.parseCodeSignature()
      } catch {
        XCTFail("Failed to parse code signature: \(error)")
      }
    }
  }
}
