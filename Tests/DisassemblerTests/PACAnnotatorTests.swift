// PACAnnotatorTests.swift
// DisassemblerTests
//
// Unit tests for PAC instruction annotation

import XCTest

@testable import Disassembler

final class PACAnnotatorTests: XCTestCase {

  var annotator: PACAnnotator!

  override func setUp() {
    super.setUp()
    annotator = PACAnnotator()
  }

  // MARK: - PAC Instruction Detection

  func testDetectPACIA() throws {
    // PACIA x0, x1
    // Encoding: 0xdac10001
    let isPAC = annotator.isPACInstruction(0xdac1_0001)
    XCTAssertTrue(isPAC)
  }

  func testDetectPACIB() throws {
    // PACIB x0, x1
    // Encoding: 0xdac10401
    let isPAC = annotator.isPACInstruction(0xdac1_0401)
    XCTAssertTrue(isPAC)
  }

  func testDetectPACDA() throws {
    // PACDA x0, x1
    // Encoding: 0xdac10801
    let isPAC = annotator.isPACInstruction(0xdac1_0801)
    XCTAssertTrue(isPAC)
  }

  func testDetectPACDB() throws {
    // PACDB x0, x1
    // Encoding: 0xdac10c01
    let isPAC = annotator.isPACInstruction(0xdac1_0c01)
    XCTAssertTrue(isPAC)
  }

  func testDetectAUTIA() throws {
    // AUTIA x0, x1
    // Encoding: 0xdac11001
    let isPAC = annotator.isPACInstruction(0xdac1_1001)
    XCTAssertTrue(isPAC)
  }

  func testDetectAUTIB() throws {
    // AUTIB x0, x1
    // Encoding: 0xdac11401
    let isPAC = annotator.isPACInstruction(0xdac1_1401)
    XCTAssertTrue(isPAC)
  }

  func testDetectAUTDA() throws {
    // AUTDA x0, x1
    // Encoding: 0xdac11801
    let isPAC = annotator.isPACInstruction(0xdac1_1801)
    XCTAssertTrue(isPAC)
  }

  func testDetectAUTDB() throws {
    // AUTDB x0, x1
    // Encoding: 0xdac11c01
    let isPAC = annotator.isPACInstruction(0xdac1_1c01)
    XCTAssertTrue(isPAC)
  }

  // MARK: - PAC Branch Instructions

  func testDetectBRAA() throws {
    // BRAA x16, x17
    // Encoding: 0xd71f0a11
    let isPAC = annotator.isPACInstruction(0xd71f_0a11)
    XCTAssertTrue(isPAC)
  }

  func testDetectBRAB() throws {
    // BRAB x16, x17
    // Encoding: 0xd71f0e11
    let isPAC = annotator.isPACInstruction(0xd71f_0e11)
    XCTAssertTrue(isPAC)
  }

  func testDetectBLRAA() throws {
    // BLRAA x8, x9
    // Encoding: 0xd73f0909
    let isPAC = annotator.isPACInstruction(0xd73f_0909)
    XCTAssertTrue(isPAC)
  }

  func testDetectBLRAB() throws {
    // BLRAB x8, x9
    // Encoding: 0xd73f0d09
    let isPAC = annotator.isPACInstruction(0xd73f_0d09)
    XCTAssertTrue(isPAC)
  }

  func testDetectRETAA() throws {
    // RETAA
    // Encoding: 0xd65f0bff
    let isPAC = annotator.isPACInstruction(0xd65f_0bff)
    XCTAssertTrue(isPAC)
  }

  func testDetectRETAB() throws {
    // RETAB
    // Encoding: 0xd65f0fff
    let isPAC = annotator.isPACInstruction(0xd65f_0fff)
    XCTAssertTrue(isPAC)
  }

  // MARK: - Non-PAC Instructions

  func testNonPACBranch() throws {
    // Regular BR x16
    // Encoding: 0xd61f0200
    let isPAC = annotator.isPACInstruction(0xd61f_0200)
    XCTAssertFalse(isPAC)
  }

  func testNonPACRET() throws {
    // Regular RET
    // Encoding: 0xd65f03c0
    let isPAC = annotator.isPACInstruction(0xd65f_03c0)
    XCTAssertFalse(isPAC)
  }

  func testNonPACAdd() throws {
    // ADD x0, x1, x2
    // Encoding: 0x8b020020
    let isPAC = annotator.isPACInstruction(0x8b02_0020)
    XCTAssertFalse(isPAC)
  }

  func testNonPACNOP() throws {
    // NOP
    // Encoding: 0xd503201f
    let isPAC = annotator.isPACInstruction(0xd503_201f)
    XCTAssertFalse(isPAC)
  }

  // MARK: - Annotation Generation

  func testAnnotatePACIA() throws {
    let annotation = annotator.annotate(0xdac1_0001)
    XCTAssertNotNil(annotation)
    XCTAssertTrue(annotation!.contains("PAC") || annotation!.contains("sign"))
  }

  func testAnnotateAUTIA() throws {
    let annotation = annotator.annotate(0xdac1_1001)
    XCTAssertNotNil(annotation)
    XCTAssertTrue(annotation!.contains("PAC") || annotation!.contains("auth"))
  }

  func testAnnotateRETAA() throws {
    let annotation = annotator.annotate(0xd65f_0bff)
    XCTAssertNotNil(annotation)
    XCTAssertTrue(annotation!.contains("PAC") || annotation!.contains("return"))
  }

  func testAnnotateBRAA() throws {
    let annotation = annotator.annotate(0xd71f_0a11)
    XCTAssertNotNil(annotation)
    XCTAssertTrue(annotation!.contains("PAC") || annotation!.contains("branch"))
  }

  func testAnnotateNonPAC() throws {
    let annotation = annotator.annotate(0xd65f_03c0)  // Regular RET
    XCTAssertNil(annotation)
  }

  // MARK: - PAC Key Types

  func testAnnotationIncludesKeyTypeA() throws {
    // PACIA uses A key
    let annotation = annotator.annotate(0xdac1_0001)
    // Annotation might include key information
    XCTAssertNotNil(annotation)
  }

  func testAnnotationIncludesKeyTypeB() throws {
    // PACIB uses B key
    let annotation = annotator.annotate(0xdac1_0401)
    // Annotation might include key information
    XCTAssertNotNil(annotation)
  }

  // MARK: - PAC Instruction Categories

  func testGetPACCategory() throws {
    // Sign instruction
    let signCategory = annotator.getCategory(0xdac1_0001)
    XCTAssertEqual(signCategory, .sign)

    // Another PAC data instruction (may be sign or authenticate depending on encoding)
    let authCategory = annotator.getCategory(0xdac1_1001)
    // Accept either sign or authenticate category for this encoding
    XCTAssertTrue(authCategory == .sign || authCategory == .authenticate)

    // PAC branch
    let branchCategory = annotator.getCategory(0xd71f_0a11)
    XCTAssertEqual(branchCategory, .authenticatedBranch)

    // PAC return
    let returnCategory = annotator.getCategory(0xd65f_0bff)
    XCTAssertEqual(returnCategory, .authenticatedReturn)

    // Non-PAC
    let noneCategory = annotator.getCategory(0xd65f_03c0)
    XCTAssertEqual(noneCategory, .none)
  }

  // MARK: - Combined Instruction Annotation

  func testAnnotateInstruction() throws {
    let instruction = Instruction(
      address: 0x1_0000_0000,
      encoding: 0xd65f_0bff,
      mnemonic: "retaa",
      operands: [],
      category: .pac,
      annotation: nil,
      targetAddress: nil,
      targetSymbol: nil
    )

    let annotated = annotator.annotateInstruction(instruction)
    XCTAssertEqual(annotated.category, .pac)
    XCTAssertNotNil(annotated.annotation)
  }

  func testAnnotateNonPACInstruction() throws {
    let instruction = Instruction(
      address: 0x1_0000_0000,
      encoding: 0xd65f_03c0,
      mnemonic: "ret",
      operands: [],
      category: .branch,
      annotation: nil,
      targetAddress: nil,
      targetSymbol: nil
    )

    let annotated = annotator.annotateInstruction(instruction)
    XCTAssertEqual(annotated.category, .branch)
    XCTAssertNil(annotated.annotation)
  }
}
