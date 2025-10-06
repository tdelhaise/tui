import XCTest
import CNcursesShims
@testable import TextUserInterfaceApp
@testable import Editors

final class TextUserInterfaceAppTests: XCTestCase {
	@MainActor
	private func makeApp(lines: [String], cursorRow: Int = 0, cursorCol: Int = 0) -> TextUserInterfaceApp {
		let app = TextUserInterfaceApp()
		let buffer = EditorBuffer(lines: lines, cursorRow: cursorRow, cursorCol: cursorCol)
		app._debugSetBuffer(buffer)
		return app
	}

	func testMetaWordSequenceBackward() throws {
		try runOnMainActor(description: #function) { [self] in
			let app = self.makeApp(lines: ["foo bar baz"], cursorRow: 0, cursorCol: 7)
			XCTAssertTrue(app._debugHandleMetaWordSequence("b"))
			let buffer = try XCTUnwrap(app._debugBuffer())
			XCTAssertEqual(buffer.cursorCol, 4)
			XCTAssertFalse(buffer.hasSelection)
		}
	}

	func testMetaWordSequenceForwardWithSelection() throws {
		try runOnMainActor(description: #function) { [self] in
			let app = self.makeApp(lines: ["foo bar baz"], cursorRow: 0, cursorCol: 0)
			XCTAssertTrue(app._debugHandleMetaWordSequence("F"))
			let buffer = try XCTUnwrap(app._debugBuffer())
			XCTAssertEqual(buffer.cursorCol, 3)
			XCTAssertEqual(buffer.selectionLength(), 3)
		}
	}

	func testArrowEscapeSequenceOptionLeft() throws {
		try runOnMainActor(description: #function) { [self] in
			let app = self.makeApp(lines: ["foo bar baz"], cursorRow: 0, cursorCol: 8)
			let sequence: [Int32] = [91, 49, 59, 51, 68] // "[1;3D"
			XCTAssertTrue(app._debugHandleArrowEscapeSequence(sequence))
			let buffer = try XCTUnwrap(app._debugBuffer())
			XCTAssertEqual(buffer.cursorCol, 4)
			XCTAssertFalse(buffer.hasSelection)
		}
	}

	func testArrowEscapeSequenceOptionShiftRightSelects() throws {
		try runOnMainActor(description: #function) { [self] in
			let app = self.makeApp(lines: ["foo bar baz"], cursorRow: 0, cursorCol: 4)
			let sequence: [Int32] = [91, 49, 59, 52, 67] // "[1;4C"
			XCTAssertTrue(app._debugHandleArrowEscapeSequence(sequence))
			let buffer = try XCTUnwrap(app._debugBuffer())
			XCTAssertEqual(buffer.cursorCol, 7)
			XCTAssertEqual(buffer.selectionLength(), 3)
		}
	}


	func testArrowEscapeSequenceCursesKeyCodes() throws {
		try runOnMainActor(description: #function) { [self] in
			let optionLeftRaw: Int32 = 0x221
			let optionRightRaw: Int32 = 0x230
			let shiftOptionLeftRaw: Int32 = 0x222
			let shiftOptionRightRaw: Int32 = 0x231

			var app = self.makeApp(lines: ["foo bar baz"], cursorRow: 0, cursorCol: 7)
			XCTAssertTrue(app._debugHandleArrowEscapeSequence([KEY_LEFT]))
			var buffer = try XCTUnwrap(app._debugBuffer())
			XCTAssertEqual(buffer.cursorCol, 4)
			XCTAssertFalse(buffer.hasSelection)
			XCTAssertTrue(app._debugHandleArrowEscapeSequence([KEY_SRIGHT]))
			buffer = try XCTUnwrap(app._debugBuffer())
			XCTAssertEqual(buffer.cursorCol, 7)
			XCTAssertEqual(buffer.selectionLength(), 3)

			app = self.makeApp(lines: ["foo bar baz"], cursorRow: 0, cursorCol: 7)
			XCTAssertTrue(app._debugHandleArrowEscapeSequence([optionLeftRaw]))
			buffer = try XCTUnwrap(app._debugBuffer())
			XCTAssertEqual(buffer.cursorCol, 4)
			XCTAssertFalse(buffer.hasSelection)
			XCTAssertTrue(app._debugHandleArrowEscapeSequence([shiftOptionRightRaw]))
			buffer = try XCTUnwrap(app._debugBuffer())
			XCTAssertEqual(buffer.cursorCol, 7)
			XCTAssertEqual(buffer.selectionLength(), 3)

			app = self.makeApp(lines: ["foo bar baz"], cursorRow: 0, cursorCol: 4)
			XCTAssertTrue(app._debugHandleArrowEscapeSequence([optionRightRaw]))
			buffer = try XCTUnwrap(app._debugBuffer())
			XCTAssertEqual(buffer.cursorCol, 7)
			XCTAssertFalse(buffer.hasSelection)
			XCTAssertTrue(app._debugHandleArrowEscapeSequence([shiftOptionLeftRaw]))
			buffer = try XCTUnwrap(app._debugBuffer())
			XCTAssertEqual(buffer.cursorCol, 4)
			XCTAssertTrue(buffer.hasSelection)
		}
	}


	func testArrowEscapeSequenceCursesVerticalKeyCodes() throws {
		try runOnMainActor(description: #function) { [self] in
			let app = self.makeApp(lines: ["foo", "bar", "baz"], cursorRow: 1, cursorCol: 1)
			XCTAssertTrue(app._debugHandleArrowEscapeSequence([KEY_UP]))
			var buffer = try XCTUnwrap(app._debugBuffer())
			XCTAssertEqual(buffer.cursorRow, 0)
			XCTAssertEqual(buffer.cursorCol, 1)
			XCTAssertFalse(buffer.hasSelection)
			XCTAssertTrue(app._debugHandleArrowEscapeSequence([KEY_DOWN]))
			buffer = try XCTUnwrap(app._debugBuffer())
			XCTAssertEqual(buffer.cursorRow, 1)
			XCTAssertEqual(buffer.cursorCol, 1)
			XCTAssertFalse(buffer.hasSelection)
		}
	}

	func testKeyInspectorCapturesMetaSequence() throws {
		try runOnMainActor(description: #function) { [self] in
			let app = self.makeApp(lines: ["foo bar"], cursorRow: 0, cursorCol: 7)
			app._debugEnableInspector()
			XCTAssertTrue(app._debugHandleEscapeSequence(codes: [Int32(98)]))
			let notes = app._debugInspectorNotes()
			XCTAssertEqual(notes.last, "62|meta previousWord selecting=false")
		}
	}

	func testKeyInspectorCapturesRawKeyCodes() throws {
		try runOnMainActor(description: #function) { [self] in
			let app = self.makeApp(lines: ["foo bar baz"], cursorRow: 0, cursorCol: 4)
			app._debugEnableInspector()
			XCTAssertTrue(app._debugHandleArrowEscapeSequence([Int32(0x230)]))
			let notes = app._debugInspectorNotes()
			XCTAssertEqual(notes.last, "230|word right")
		}
	}

	func testHandleEscapeSequenceDelegatesToMetaWord() throws {
		try runOnMainActor(description: #function) { [self] in
			let app = self.makeApp(lines: ["alpha beta"], cursorRow: 0, cursorCol: 5)
			XCTAssertTrue(app._debugHandleEscapeSequence(codes: [98]))
			let buffer = try XCTUnwrap(app._debugBuffer())
			XCTAssertEqual(buffer.cursorCol, 0)
		}
	}

	func testHandleEscapeSequenceFallsBackToArrowSequence() throws {
		try runOnMainActor(description: #function) { [self] in
			let app = self.makeApp(lines: ["alpha beta"], cursorRow: 0, cursorCol: 5)
			let sequence: [Int32] = [91, 49, 59, 51, 68]
			XCTAssertTrue(app._debugHandleEscapeSequence(codes: sequence))
			let buffer = try XCTUnwrap(app._debugBuffer())
			XCTAssertEqual(buffer.cursorCol, 0)
		}
	}

	func testEscapeSequenceShiftDetection() throws {
		try runOnMainActor(description: #function) { [self] in
			let app = self.makeApp(lines: ["foo"], cursorRow: 0, cursorCol: 0)
			XCTAssertTrue(app._debugEscapeSequenceHasShiftModifier("[1;4C"))
			XCTAssertTrue(app._debugEscapeSequenceHasShiftModifier("[1;10D"))
			XCTAssertFalse(app._debugEscapeSequenceHasShiftModifier("[1;3D"))
		}
	}
}
