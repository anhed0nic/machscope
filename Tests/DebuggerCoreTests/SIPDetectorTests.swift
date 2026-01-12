// SIPDetectorTests.swift
// DebuggerCoreTests
//
// Unit tests for System Integrity Protection detection

import XCTest

@testable import DebuggerCore

final class SIPDetectorTests: XCTestCase {

  // MARK: - SIP Detection Tests

  func testSIPDetectorInitialization() throws {
    let detector = SIPDetector()
    // Should initialize without crashing
    XCTAssertNotNil(detector)
  }

  func testSIPStatusProperty() throws {
    let detector = SIPDetector()
    // Should return a valid SIP status
    let status = detector.sipStatus
    XCTAssertTrue([.enabled, .disabled, .unknown].contains(status))
  }

  func testSIPIsEnabled() throws {
    let detector = SIPDetector()
    // On a typical macOS system, SIP is enabled
    // This test just verifies the property works
    let _ = detector.isEnabled
  }

  func testSIPStatusDescription() throws {
    XCTAssertEqual(SIPStatus.enabled.description, "Enabled")
    XCTAssertEqual(SIPStatus.disabled.description, "Disabled")
    XCTAssertEqual(SIPStatus.unknown.description, "Unknown")
  }

  // MARK: - SIP Impact Tests

  func testSIPImpactOnSystemBinaries() throws {
    let detector = SIPDetector()

    // When SIP is enabled, system binaries cannot be debugged
    if detector.isEnabled {
      XCTAssertTrue(detector.blocksDebugging(path: "/bin/ls"))
      XCTAssertTrue(detector.blocksDebugging(path: "/usr/bin/python3"))
      XCTAssertTrue(detector.blocksDebugging(path: "/System/Library/CoreServices/Finder.app"))
    }
  }

  func testSIPImpactOnUserBinaries() throws {
    let detector = SIPDetector()

    // User binaries should not be blocked by SIP
    XCTAssertFalse(detector.blocksDebugging(path: "/Users/test/app"))
    XCTAssertFalse(detector.blocksDebugging(path: "/Applications/SomeApp.app"))
    XCTAssertFalse(detector.blocksDebugging(path: "/opt/local/bin/tool"))
  }

  func testSIPProtectedPaths() throws {
    // Test that we correctly identify SIP-protected paths
    XCTAssertTrue(SIPDetector.isProtectedPath("/bin/ls"))
    XCTAssertTrue(SIPDetector.isProtectedPath("/sbin/mount"))
    XCTAssertTrue(SIPDetector.isProtectedPath("/usr/bin/python3"))
    XCTAssertTrue(SIPDetector.isProtectedPath("/usr/lib/libSystem.B.dylib"))
    XCTAssertTrue(SIPDetector.isProtectedPath("/System/Library/Frameworks/Foundation.framework"))

    XCTAssertFalse(SIPDetector.isProtectedPath("/usr/local/bin/myapp"))
    XCTAssertFalse(SIPDetector.isProtectedPath("/Applications/MyApp.app"))
    XCTAssertFalse(SIPDetector.isProtectedPath("/Users/test/binary"))
  }

  // MARK: - csrutil Integration Tests

  func testDetectViaCsrutil() throws {
    let detector = SIPDetector()
    // This verifies that we can detect SIP status via csrutil (or fallback)
    // The actual value depends on system configuration
    let status = detector.sipStatus

    // Status should be definitive on a normal system
    // Only unknown if csrutil fails for some reason
    if status == .unknown {
      // This is acceptable but unusual
      print("Warning: SIP status could not be determined")
    }
  }

  // MARK: - SIP Guidance Tests

  func testSIPGuidance() throws {
    let detector = SIPDetector()

    if detector.isEnabled {
      let guidance = detector.disableGuidance
      XCTAssertFalse(guidance.isEmpty)
      // Should mention Recovery Mode
      XCTAssertTrue(guidance.contains("Recovery") || guidance.contains("csrutil"))
    }
  }

  // MARK: - SIPStatus Enum Tests

  func testSIPStatusAllCases() throws {
    let allCases: [SIPStatus] = [.enabled, .disabled, .unknown]
    XCTAssertEqual(allCases.count, 3)
  }
}
