// PermissionTests.swift
// DebuggerCoreTests
//
// Unit tests for permission detection

import XCTest

@testable import DebuggerCore

final class PermissionTests: XCTestCase {

  // MARK: - PermissionTier Tests

  func testPermissionTierFull() throws {
    // Full tier should allow debugging
    let tier = PermissionTier.full
    XCTAssertTrue(tier.canDebug)
    XCTAssertTrue(tier.canDisassemble)
    XCTAssertTrue(tier.canParse)
  }

  func testPermissionTierAnalysis() throws {
    // Analysis tier should not allow debugging but allow disassembly
    let tier = PermissionTier.analysis
    XCTAssertFalse(tier.canDebug)
    XCTAssertTrue(tier.canDisassemble)
    XCTAssertTrue(tier.canParse)
  }

  func testPermissionTierReadOnly() throws {
    // ReadOnly tier should only allow parsing
    let tier = PermissionTier.readOnly
    XCTAssertFalse(tier.canDebug)
    XCTAssertFalse(tier.canDisassemble)
    XCTAssertTrue(tier.canParse)
  }

  func testPermissionTierDescriptions() throws {
    XCTAssertEqual(PermissionTier.full.description, "Full")
    XCTAssertEqual(PermissionTier.analysis.description, "Analysis")
    XCTAssertEqual(PermissionTier.readOnly.description, "Read-Only")
  }

  // MARK: - PermissionChecker Tests

  func testPermissionCheckerInitialization() throws {
    let checker = PermissionChecker()
    // Should return a valid tier
    let tier = checker.tier
    XCTAssertTrue([.full, .analysis, .readOnly].contains(tier))
  }

  func testPermissionCheckerCanDebug() throws {
    let checker = PermissionChecker()
    // canDebug should match tier
    XCTAssertEqual(checker.canDebug, checker.tier == .full)
  }

  func testPermissionCheckerStatus() throws {
    let checker = PermissionChecker()
    let status = checker.status

    // Status should be a valid PermissionStatus with all fields
    // We verify by accessing all properties (will fail to compile if missing)
    _ = status.staticAnalysis
    _ = status.disassembly
    _ = status.debugging
    _ = status.sipEnabled
    _ = status.developerToolsEnabled
    _ = status.debuggerEntitlement

    // Also verify the statusDictionary has correct keys
    let dict = checker.statusDictionary
    XCTAssertTrue(dict.keys.contains("staticAnalysis"))
    XCTAssertTrue(dict.keys.contains("disassembly"))
    XCTAssertTrue(dict.keys.contains("debugging"))
    XCTAssertTrue(dict.keys.contains("sipEnabled"))
    XCTAssertTrue(dict.keys.contains("developerTools"))
    XCTAssertTrue(dict.keys.contains("debuggerEntitlement"))
  }

  func testPermissionCheckerGuidanceForMissingPermissions() throws {
    let checker = PermissionChecker()
    let guidance = checker.guidance

    // If not full tier, should have guidance
    if checker.tier != .full {
      XCTAssertFalse(guidance.isEmpty)
      // Guidance should mention System Settings
      XCTAssertTrue(guidance.contains("System Settings") || guidance.contains("System Preferences"))
    }
  }

  // MARK: - EntitlementValidator Tests

  func testEntitlementValidatorCurrentProcess() throws {
    let validator = EntitlementValidator()
    // The test process typically doesn't have debugger entitlement
    // This test verifies the method runs without crashing
    _ = validator.hasDebuggerEntitlement(forCurrentProcess: true)
  }

  func testEntitlementValidatorDeveloperToolsCheck() throws {
    let validator = EntitlementValidator()
    // Should return a boolean without crashing
    let _ = validator.developerToolsEnabled
  }

  // MARK: - Permission Status Model Tests

  func testPermissionStatusIsComplete() throws {
    let status = PermissionStatus(
      staticAnalysis: true,
      disassembly: true,
      debugging: false,
      sipEnabled: true,
      developerToolsEnabled: false,
      debuggerEntitlement: false
    )

    XCTAssertTrue(status.staticAnalysis)
    XCTAssertTrue(status.disassembly)
    XCTAssertFalse(status.debugging)
    XCTAssertTrue(status.sipEnabled)
    XCTAssertFalse(status.developerToolsEnabled)
    XCTAssertFalse(status.debuggerEntitlement)
  }

  func testPermissionStatusDeterminedTier() throws {
    // Full capabilities
    let fullStatus = PermissionStatus(
      staticAnalysis: true,
      disassembly: true,
      debugging: true,
      sipEnabled: false,
      developerToolsEnabled: true,
      debuggerEntitlement: true
    )
    XCTAssertEqual(fullStatus.tier, .full)

    // Analysis only
    let analysisStatus = PermissionStatus(
      staticAnalysis: true,
      disassembly: true,
      debugging: false,
      sipEnabled: true,
      developerToolsEnabled: false,
      debuggerEntitlement: false
    )
    XCTAssertEqual(analysisStatus.tier, .analysis)
  }

  // MARK: - JSON Output Tests

  func testPermissionStatusJSONEncoding() throws {
    let status = PermissionStatus(
      staticAnalysis: true,
      disassembly: true,
      debugging: false,
      sipEnabled: true,
      developerToolsEnabled: false,
      debuggerEntitlement: false
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    let data = try encoder.encode(status)
    let json = String(data: data, encoding: .utf8)!

    XCTAssertTrue(json.contains("\"staticAnalysis\" : true"))
    XCTAssertTrue(json.contains("\"debugging\" : false"))
    XCTAssertTrue(json.contains("\"sipEnabled\" : true"))
  }
}
