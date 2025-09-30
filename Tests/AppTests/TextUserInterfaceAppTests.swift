import XCTest
@testable import TextUserInterfaceApp
@testable import Editors

@MainActor
final class TextUserInterfaceAppTests: XCTestCase {
	private func makeApp(lines: [String], cursorRow: Int = 0, cursorCol: Int = 0) -> TextUserInterfaceApp {
		let app = TextUserInterfaceApp()
		let buffer = EditorBuffer(lines: lines, cursorRow: cursorRow, cursorCol: cursorCol)
		app._debugSetBuffer(buffer)
		return app
	}

	func testMetaWordSequenceBackward() throws {
		let app = makeApp(lines: ["foo bar baz"], cursorRow: 0, cursorCol: 7)
		XCTAssertTrue(app._debugHandleMetaWordSequence("b"))
		let buffer = try XCTUnwrap(app._debugBuffer())
		XCTAssertEqual(buffer.cursorCol, 4)
		XCTAssertFalse(buffer.hasSelection)
	}

	func testMetaWordSequenceForwardWithSelection() throws {
		let app = makeApp(lines: ["foo bar baz"], cursorRow: 0, cursorCol: 0)
		XCTAssertTrue(app._debugHandleMetaWordSequence("F"))
		let buffer = try XCTUnwrap(app._debugBuffer())
		XCTAssertEqual(buffer.cursorCol, 3)
		XCTAssertEqual(buffer.selectionLength(), 3)
	}

	func testArrowEscapeSequenceOptionLeft() throws {
		let app = makeApp(lines: ["foo bar baz"], cursorRow: 0, cursorCol: 8)
		let sequence: [Int32] = [91, 49, 59, 51, 68] // "[1;3D"
		XCTAssertTrue(app._debugHandleArrowEscapeSequence(sequence))
		let buffer = try XCTUnwrap(app._debugBuffer())
		XCTAssertEqual(buffer.cursorCol, 4)
		XCTAssertFalse(buffer.hasSelection)
	}

	func testArrowEscapeSequenceOptionShiftRightSelects() throws {
		let app = makeApp(lines: ["foo bar baz"], cursorRow: 0, cursorCol: 4)
		let sequence: [Int32] = [91, 49, 59, 52, 67] // "[1;4C"
		XCTAssertTrue(app._debugHandleArrowEscapeSequence(sequence))
		let buffer = try XCTUnwrap(app._debugBuffer())
		XCTAssertEqual(buffer.cursorCol, 7)
		XCTAssertEqual(buffer.selectionLength(), 3)
	}

	func testHandleEscapeSequenceDelegatesToMetaWord() throws {
		let app = makeApp(lines: ["alpha beta"], cursorRow: 0, cursorCol: 5)
		XCTAssertTrue(app._debugHandleEscapeSequence(codes: [98]))
		let buffer = try XCTUnwrap(app._debugBuffer())
		XCTAssertEqual(buffer.cursorCol, 0)
	}

	func testHandleEscapeSequenceFallsBackToArrowSequence() throws {
		let app = makeApp(lines: ["alpha beta"], cursorRow: 0, cursorCol: 5)
		let sequence: [Int32] = [91, 49, 59, 51, 68]
		XCTAssertTrue(app._debugHandleEscapeSequence(codes: sequence))
		let buffer = try XCTUnwrap(app._debugBuffer())
		XCTAssertEqual(buffer.cursorCol, 0)
	}

	func testEscapeSequenceShiftDetection() throws {
		let app = makeApp(lines: ["foo"], cursorRow: 0, cursorCol: 0)
		XCTAssertTrue(app._debugEscapeSequenceHasShiftModifier("[1;4C"))
		XCTAssertTrue(app._debugEscapeSequenceHasShiftModifier("[1;10D"))
		XCTAssertFalse(app._debugEscapeSequenceHasShiftModifier("[1;3D"))
	}
}
