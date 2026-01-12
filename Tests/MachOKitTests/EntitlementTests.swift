// EntitlementTests.swift
// MachOKitTests
//
// Tests for entitlements parsing

import XCTest

@testable import MachOKit

final class EntitlementTests: XCTestCase {

  // MARK: - XML Entitlements Parsing

  func testParseSimpleXMLEntitlements() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
          <key>com.apple.security.get-task-allow</key>
          <true/>
      </dict>
      </plist>
      """

    let data = xml.data(using: .utf8)!
    let entitlements = try Entitlements.parseXML(from: data)

    XCTAssertEqual(entitlements.format, .xml)
    XCTAssertEqual(entitlements.count, 1)
    XCTAssertTrue(entitlements.hasGetTaskAllow)
    XCTAssertNotNil(entitlements.rawXML)
  }

  func testParseMultipleEntitlements() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
          <key>com.apple.security.cs.debugger</key>
          <true/>
          <key>com.apple.security.get-task-allow</key>
          <true/>
          <key>com.apple.security.app-sandbox</key>
          <false/>
          <key>com.apple.developer.team-identifier</key>
          <string>ABCD1234</string>
      </dict>
      </plist>
      """

    let data = xml.data(using: .utf8)!
    let entitlements = try Entitlements.parseXML(from: data)

    XCTAssertEqual(entitlements.count, 4)
    XCTAssertTrue(entitlements.hasDebuggerEntitlement)
    XCTAssertTrue(entitlements.hasGetTaskAllow)
    XCTAssertFalse(entitlements.isAppSandboxed)
    XCTAssertEqual(entitlements.teamIdentifier, "ABCD1234")
  }

  func testParseEntitlementsWithArray() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
          <key>keychain-access-groups</key>
          <array>
              <string>$(AppIdentifierPrefix)com.example.app</string>
              <string>$(AppIdentifierPrefix)com.example.shared</string>
          </array>
      </dict>
      </plist>
      """

    let data = xml.data(using: .utf8)!
    let entitlements = try Entitlements.parseXML(from: data)

    XCTAssertEqual(entitlements.count, 1)

    let groups = entitlements.keychainAccessGroups
    XCTAssertNotNil(groups)
    XCTAssertEqual(groups?.count, 2)
    XCTAssertEqual(groups?[0], "$(AppIdentifierPrefix)com.example.app")
  }

  func testParseEmptyEntitlements() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
      </dict>
      </plist>
      """

    let data = xml.data(using: .utf8)!
    let entitlements = try Entitlements.parseXML(from: data)

    XCTAssertTrue(entitlements.isEmpty)
    XCTAssertEqual(entitlements.count, 0)
  }

  func testParseInvalidXML() {
    let invalid = "not valid xml"
    let data = invalid.data(using: .utf8)!

    XCTAssertThrowsError(try Entitlements.parseXML(from: data)) { error in
      guard case MachOParseError.invalidEntitlementsFormat = error else {
        XCTFail("Expected invalidEntitlementsFormat error")
        return
      }
    }
  }

  func testParseXMLWithNonDictRoot() {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <plist version="1.0">
      <array>
          <string>item</string>
      </array>
      </plist>
      """

    let data = xml.data(using: .utf8)!

    XCTAssertThrowsError(try Entitlements.parseXML(from: data)) { error in
      guard case MachOParseError.invalidEntitlementsFormat = error else {
        XCTFail("Expected invalidEntitlementsFormat error")
        return
      }
    }
  }

  // MARK: - Value Accessors

  func testBoolValueAccessor() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <plist version="1.0">
      <dict>
          <key>bool-true</key>
          <true/>
          <key>bool-false</key>
          <false/>
          <key>string-value</key>
          <string>text</string>
      </dict>
      </plist>
      """

    let data = xml.data(using: .utf8)!
    let entitlements = try Entitlements.parseXML(from: data)

    XCTAssertEqual(entitlements.boolValue(for: "bool-true"), true)
    XCTAssertEqual(entitlements.boolValue(for: "bool-false"), false)
    XCTAssertNil(entitlements.boolValue(for: "string-value"))
    XCTAssertNil(entitlements.boolValue(for: "nonexistent"))
  }

  func testStringValueAccessor() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <plist version="1.0">
      <dict>
          <key>string-value</key>
          <string>hello world</string>
          <key>bool-value</key>
          <true/>
      </dict>
      </plist>
      """

    let data = xml.data(using: .utf8)!
    let entitlements = try Entitlements.parseXML(from: data)

    XCTAssertEqual(entitlements.stringValue(for: "string-value"), "hello world")
    XCTAssertNil(entitlements.stringValue(for: "bool-value"))
    XCTAssertNil(entitlements.stringValue(for: "nonexistent"))
  }

  func testArrayValueAccessor() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <plist version="1.0">
      <dict>
          <key>array-value</key>
          <array>
              <string>one</string>
              <string>two</string>
          </array>
          <key>string-value</key>
          <string>text</string>
      </dict>
      </plist>
      """

    let data = xml.data(using: .utf8)!
    let entitlements = try Entitlements.parseXML(from: data)

    let array = entitlements.arrayValue(for: "array-value")
    XCTAssertNotNil(array)
    XCTAssertEqual(array?.count, 2)

    XCTAssertNil(entitlements.arrayValue(for: "string-value"))
  }

  func testHasKeyMethod() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <plist version="1.0">
      <dict>
          <key>exists</key>
          <true/>
      </dict>
      </plist>
      """

    let data = xml.data(using: .utf8)!
    let entitlements = try Entitlements.parseXML(from: data)

    XCTAssertTrue(entitlements.hasKey("exists"))
    XCTAssertFalse(entitlements.hasKey("does-not-exist"))
  }

  func testKeysProperty() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <plist version="1.0">
      <dict>
          <key>zebra</key>
          <true/>
          <key>apple</key>
          <true/>
          <key>banana</key>
          <true/>
      </dict>
      </plist>
      """

    let data = xml.data(using: .utf8)!
    let entitlements = try Entitlements.parseXML(from: data)

    let keys = entitlements.keys
    XCTAssertEqual(keys.count, 3)
    // Keys should be sorted
    XCTAssertEqual(keys[0], "apple")
    XCTAssertEqual(keys[1], "banana")
    XCTAssertEqual(keys[2], "zebra")
  }

  // MARK: - Common Entitlement Properties

  func testSecurityEntitlementProperties() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <plist version="1.0">
      <dict>
          <key>com.apple.security.cs.debugger</key>
          <true/>
          <key>com.apple.security.get-task-allow</key>
          <true/>
          <key>com.apple.security.app-sandbox</key>
          <true/>
          <key>com.apple.security.cs.allow-jit</key>
          <true/>
          <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
          <true/>
          <key>com.apple.security.cs.disable-library-validation</key>
          <true/>
          <key>com.apple.security.network.client</key>
          <true/>
          <key>com.apple.security.network.server</key>
          <true/>
      </dict>
      </plist>
      """

    let data = xml.data(using: .utf8)!
    let entitlements = try Entitlements.parseXML(from: data)

    XCTAssertTrue(entitlements.hasDebuggerEntitlement)
    XCTAssertTrue(entitlements.hasGetTaskAllow)
    XCTAssertTrue(entitlements.isAppSandboxed)
    XCTAssertTrue(entitlements.hasAllowJIT)
    XCTAssertTrue(entitlements.hasAllowUnsignedMemory)
    XCTAssertTrue(entitlements.hasDisableLibraryValidation)
    XCTAssertTrue(entitlements.hasNetworkClient)
    XCTAssertTrue(entitlements.hasNetworkServer)
  }

  func testSecurityEntitlementDefaultsFalse() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <plist version="1.0">
      <dict>
      </dict>
      </plist>
      """

    let data = xml.data(using: .utf8)!
    let entitlements = try Entitlements.parseXML(from: data)

    XCTAssertFalse(entitlements.hasDebuggerEntitlement)
    XCTAssertFalse(entitlements.hasGetTaskAllow)
    XCTAssertFalse(entitlements.isAppSandboxed)
    XCTAssertFalse(entitlements.hasAllowJIT)
    XCTAssertFalse(entitlements.hasNetworkClient)
  }

  // MARK: - DER Parsing

  func testParseDEREmptyData() throws {
    let data = Data()
    let entitlements = try Entitlements.parseDER(from: data)

    XCTAssertEqual(entitlements.format, .der)
    XCTAssertTrue(entitlements.isEmpty)
    XCTAssertNotNil(entitlements.rawDER)
  }

  func testParseDERInvalidData() throws {
    let data = Data([0x01, 0x02, 0x03, 0x04])
    let entitlements = try Entitlements.parseDER(from: data)

    // Should not throw, but should have empty entries
    XCTAssertEqual(entitlements.format, .der)
    XCTAssertTrue(entitlements.isEmpty)
  }

  // MARK: - Description Tests

  func testEntitlementsDescription() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <plist version="1.0">
      <dict>
          <key>com.apple.security.get-task-allow</key>
          <true/>
          <key>application-identifier</key>
          <string>TEAM.com.example.app</string>
      </dict>
      </plist>
      """

    let data = xml.data(using: .utf8)!
    let entitlements = try Entitlements.parseXML(from: data)

    let description = entitlements.description
    XCTAssertTrue(description.contains("Entitlements"))
    XCTAssertTrue(description.contains("XML"))
    XCTAssertTrue(description.contains("2 entries"))
  }

  func testEntitlementsFormatDescription() {
    XCTAssertEqual(EntitlementsFormat.xml.description, "XML")
    XCTAssertEqual(EntitlementsFormat.der.description, "DER")
  }

  // MARK: - Edge Cases

  func testEntitlementsWithSpecialCharacters() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <plist version="1.0">
      <dict>
          <key>key-with-special-chars</key>
          <string>&lt;tag&gt; &amp; "quotes"</string>
      </dict>
      </plist>
      """

    let data = xml.data(using: .utf8)!
    let entitlements = try Entitlements.parseXML(from: data)

    let value = entitlements.stringValue(for: "key-with-special-chars")
    XCTAssertEqual(value, "<tag> & \"quotes\"")
  }

  func testEntitlementsWithUnicode() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <plist version="1.0">
      <dict>
          <key>unicode-key</key>
          <string>Hello 世界 🌍</string>
      </dict>
      </plist>
      """

    let data = xml.data(using: .utf8)!
    let entitlements = try Entitlements.parseXML(from: data)

    let value = entitlements.stringValue(for: "unicode-key")
    XCTAssertEqual(value, "Hello 世界 🌍")
  }
}
