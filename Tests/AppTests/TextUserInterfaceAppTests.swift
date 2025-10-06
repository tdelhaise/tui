import XCTest
import Foundation
import CNcursesShims
@testable import TextUserInterfaceApp
@testable import Editors

final class TextUserInterfaceAppTests: XCTestCase {
	@MainActor
	private static func makeApp(lines: [String], cursorRow: Int = 0, cursorCol: Int = 0) -> TextUserInterfaceApp {
		let app = TextUserInterfaceApp()
		let buffer = EditorBuffer(lines: lines, cursorRow: cursorRow, cursorCol: cursorCol)
		app._debugSetBuffer(buffer)
		return app
	}

	func testMetaWordSequenceBackward() throws {
		try runOnMainActor(description: #function) {
			let app = TextUserInterfaceAppTests.makeApp(lines: ["foo bar baz"], cursorRow: 0, cursorCol: 7)
			XCTAssertTrue(app._debugHandleMetaWordSequence("b"))
			let buffer = try XCTUnwrap(app._debugBuffer())
			XCTAssertEqual(buffer.cursorCol, 4)
			XCTAssertFalse(buffer.hasSelection)
		}
	}

	func testMetaWordSequenceForwardWithSelection() throws {
		try runOnMainActor(description: #function) {
			let app = TextUserInterfaceAppTests.makeApp(lines: ["foo bar baz"], cursorRow: 0, cursorCol: 0)
			XCTAssertTrue(app._debugHandleMetaWordSequence("F"))
			let buffer = try XCTUnwrap(app._debugBuffer())
			XCTAssertEqual(buffer.cursorCol, 3)
			XCTAssertEqual(buffer.selectionLength(), 3)
		}
	}

	func testArrowEscapeSequenceOptionLeft() throws {
		try runOnMainActor(description: #function) {
			let app = TextUserInterfaceAppTests.makeApp(lines: ["foo bar baz"], cursorRow: 0, cursorCol: 8)
			let sequence: [Int32] = [91, 49, 59, 51, 68] // "[1;3D"
			XCTAssertTrue(app._debugHandleArrowEscapeSequence(sequence))
			let buffer = try XCTUnwrap(app._debugBuffer())
			XCTAssertEqual(buffer.cursorCol, 4)
			XCTAssertFalse(buffer.hasSelection)
		}
	}

	func testArrowEscapeSequenceOptionShiftRightSelects() throws {
		try runOnMainActor(description: #function) {
			let app = TextUserInterfaceAppTests.makeApp(lines: ["foo bar baz"], cursorRow: 0, cursorCol: 4)
			let sequence: [Int32] = [91, 49, 59, 52, 67] // "[1;4C"
			XCTAssertTrue(app._debugHandleArrowEscapeSequence(sequence))
			let buffer = try XCTUnwrap(app._debugBuffer())
			XCTAssertEqual(buffer.cursorCol, 7)
			XCTAssertEqual(buffer.selectionLength(), 3)
		}
	}


	func testArrowEscapeSequenceCursesKeyCodes() throws {
		try runOnMainActor(description: #function) {
			let optionLeftRaw: Int32 = 0x221
			let optionRightRaw: Int32 = 0x230
			let shiftOptionLeftRaw: Int32 = 0x222
			let shiftOptionRightRaw: Int32 = 0x231

			var app = TextUserInterfaceAppTests.makeApp(lines: ["foo bar baz"], cursorRow: 0, cursorCol: 7)
			XCTAssertTrue(app._debugHandleArrowEscapeSequence([KEY_LEFT]))
			var buffer = try XCTUnwrap(app._debugBuffer())
			XCTAssertEqual(buffer.cursorCol, 4)
			XCTAssertFalse(buffer.hasSelection)
			XCTAssertTrue(app._debugHandleArrowEscapeSequence([KEY_SRIGHT]))
			buffer = try XCTUnwrap(app._debugBuffer())
			XCTAssertEqual(buffer.cursorCol, 7)
			XCTAssertEqual(buffer.selectionLength(), 3)

			app = TextUserInterfaceAppTests.makeApp(lines: ["foo bar baz"], cursorRow: 0, cursorCol: 7)
			XCTAssertTrue(app._debugHandleArrowEscapeSequence([optionLeftRaw]))
			buffer = try XCTUnwrap(app._debugBuffer())
			XCTAssertEqual(buffer.cursorCol, 4)
			XCTAssertFalse(buffer.hasSelection)
			XCTAssertTrue(app._debugHandleArrowEscapeSequence([shiftOptionRightRaw]))
			buffer = try XCTUnwrap(app._debugBuffer())
			XCTAssertEqual(buffer.cursorCol, 7)
			XCTAssertEqual(buffer.selectionLength(), 3)

			app = TextUserInterfaceAppTests.makeApp(lines: ["foo bar baz"], cursorRow: 0, cursorCol: 4)
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
		try runOnMainActor(description: #function) {
			let app = TextUserInterfaceAppTests.makeApp(lines: ["foo", "bar", "baz"], cursorRow: 1, cursorCol: 1)
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
		try runOnMainActor(description: #function) {
			let app = TextUserInterfaceAppTests.makeApp(lines: ["foo bar"], cursorRow: 0, cursorCol: 7)
			app._debugEnableInspector()
			XCTAssertTrue(app._debugHandleEscapeSequence(codes: [Int32(98)]))
			let notes = app._debugInspectorNotes()
			XCTAssertEqual(notes.last, "62|meta previousWord selecting=false")
		}
	}

	func testKeyInspectorCapturesRawKeyCodes() throws {
		try runOnMainActor(description: #function) {
			let app = TextUserInterfaceAppTests.makeApp(lines: ["foo bar baz"], cursorRow: 0, cursorCol: 4)
			app._debugEnableInspector()
			XCTAssertTrue(app._debugHandleArrowEscapeSequence([Int32(0x230)]))
			let notes = app._debugInspectorNotes()
			XCTAssertEqual(notes.last, "230|word right")
		}
	}

	func testHandleEscapeSequenceDelegatesToMetaWord() throws {
		try runOnMainActor(description: #function) {
			let app = TextUserInterfaceAppTests.makeApp(lines: ["alpha beta"], cursorRow: 0, cursorCol: 5)
			XCTAssertTrue(app._debugHandleEscapeSequence(codes: [98]))
			let buffer = try XCTUnwrap(app._debugBuffer())
			XCTAssertEqual(buffer.cursorCol, 0)
		}
	}

	func testHandleEscapeSequenceFallsBackToArrowSequence() throws {
		try runOnMainActor(description: #function) {
			let app = TextUserInterfaceAppTests.makeApp(lines: ["alpha beta"], cursorRow: 0, cursorCol: 5)
			let sequence: [Int32] = [91, 49, 59, 51, 68]
			XCTAssertTrue(app._debugHandleEscapeSequence(codes: sequence))
			let buffer = try XCTUnwrap(app._debugBuffer())
			XCTAssertEqual(buffer.cursorCol, 0)
		}
	}

	func testEscapeSequenceShiftDetection() throws {
		try runOnMainActor(description: #function) {
			let app = TextUserInterfaceAppTests.makeApp(lines: ["foo"], cursorRow: 0, cursorCol: 0)
			XCTAssertTrue(app._debugEscapeSequenceHasShiftModifier("[1;4C"))
			XCTAssertTrue(app._debugEscapeSequenceHasShiftModifier("[1;10D"))
			XCTAssertFalse(app._debugEscapeSequenceHasShiftModifier("[1;3D"))
		}
	}

	func testNavigationDoesNotMarkBufferDirty() throws {
		try runOnMainActor(description: #function) {
			let app = TextUserInterfaceApp()
			app._debugSetBuffer(EditorBuffer(lines: ["foo bar baz"], cursorRow: 0, cursorCol: 3))
			app._debugMarkDirty(false)
			XCTAssertTrue(app._debugHandleMetaWordSequence("f"))
			XCTAssertFalse(app._debugIsDirty())
		}
	}

	func testSaveDocumentWritesToDiskAndClearsDirty() throws {
		try runOnMainActor(description: #function) {
			let app = TextUserInterfaceApp()
			app._debugSetBuffer(EditorBuffer(lines: ["lorem", "ipsum"]))
			let tempURL = FileManager.default.temporaryDirectory
				.appendingPathComponent(UUID().uuidString)
				.appendingPathExtension("txt")
			defer { try? FileManager.default.removeItem(at: tempURL) }
			app._debugSetDocumentURL(tempURL)
			app._debugMarkDirty(true)
			XCTAssertTrue(app._debugSaveDocument())
			let written = try String(contentsOf: tempURL, encoding: .utf8)
			XCTAssertEqual(written, "lorem\nipsum")
			XCTAssertFalse(app._debugIsDirty())
		}
	}

	func testSearchCommitSelectsMatchAndRecordsHistory() throws {
		try runOnMainActor(description: #function) {
			let app = TextUserInterfaceApp()
			app._debugSetBuffer(EditorBuffer(lines: ["alpha beta gamma"], cursorRow: 0, cursorCol: 0))
			XCTAssertFalse(app._debugIsSearchMode())
			XCTAssertTrue(app._debugHandleSearchKey(47)) // '/'
			XCTAssertTrue(app._debugIsSearchMode())
			let chars = ["b", "e", "t", "a"].compactMap { $0.first?.asciiValue }.map(Int32.init)
			for key in chars {
				XCTAssertTrue(app._debugHandleSearchKey(key))
			}
			XCTAssertTrue(app._debugHandleSearchKey(10)) // Enter
			XCTAssertFalse(app._debugIsSearchMode())
			let buffer = try XCTUnwrap(app._debugBuffer())
			XCTAssertEqual(buffer.selectionLength(), 4)
			XCTAssertEqual(buffer.cursorCol, 10)
			XCTAssertEqual(app._debugLastSearchQuery(), "beta")
			let depths = app._debugNavigationDepths()
			XCTAssertEqual(depths.back, 1)
			XCTAssertEqual(depths.forward, 0)
			XCTAssertTrue(app._debugNavigateBack())
			let backBuffer = try XCTUnwrap(app._debugBuffer())
			XCTAssertEqual(backBuffer.cursorCol, 0)
			XCTAssertTrue(app._debugNavigateForward())
			let forwardBuffer = try XCTUnwrap(app._debugBuffer())
			XCTAssertEqual(forwardBuffer.cursorCol, 10)
		}
	}

	func testCommandPaletteStubOpensAndCancels() throws {
		try runOnMainActor(description: #function) {
			let app = TextUserInterfaceApp()
			app._debugSetBuffer(EditorBuffer(lines: ["foo"], cursorRow: 0, cursorCol: 0))
			XCTAssertFalse(app._debugIsCommandPaletteMode())
			XCTAssertTrue(app._debugHandleCommandKey(58))
			XCTAssertTrue(app._debugIsCommandPaletteMode())
			let pKey = Int32(Character("p").asciiValue!)
			XCTAssertTrue(app._debugHandleCommandKey(pKey))
			XCTAssertEqual(app._debugCommandPaletteQuery(), "p")
			XCTAssertTrue(app._debugHandleCommandKey(27))
			XCTAssertFalse(app._debugIsCommandPaletteMode())
		}
	}

	func testRepeatSearchAdvancesThroughMatches() throws {
		try runOnMainActor(description: #function) {
			let app = TextUserInterfaceApp()
			app._debugSetBuffer(EditorBuffer(lines: ["foo bar foo"], cursorRow: 0, cursorCol: 0))
			let fooKeys = ["f", "o", "o"].compactMap { $0.first?.asciiValue }.map(Int32.init)
			XCTAssertTrue(app._debugHandleSearchKey(47))
			for key in fooKeys {
				XCTAssertTrue(app._debugHandleSearchKey(key))
			}
			XCTAssertTrue(app._debugHandleSearchKey(10))
			let first = try XCTUnwrap(app._debugBuffer())
			XCTAssertEqual(first.cursorCol, 3)
			XCTAssertTrue(app._debugHandleSearchKey(110)) // 'n'
			let second = try XCTUnwrap(app._debugBuffer())
			XCTAssertEqual(second.cursorCol, 11)
			XCTAssertTrue(app._debugHandleSearchKey(78)) // 'N'
			let third = try XCTUnwrap(app._debugBuffer())
			XCTAssertEqual(third.cursorCol, 3)
		}
	}
}
