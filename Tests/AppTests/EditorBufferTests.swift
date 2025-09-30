import XCTest
import Foundation
@testable import Editors

final class EditorBufferTests: XCTestCase {
	func testLineNavigation() {
		var buffer = EditorBuffer(lines: ["let foo = 1", "    bar baz"])
		buffer.moveCursorTo(row: 0, column: 5)
		buffer.moveToLineStart()
		XCTAssertEqual(buffer.cursorRow, 0)
		XCTAssertEqual(buffer.cursorCol, 0)
		buffer.moveToLineEnd()
		XCTAssertEqual(buffer.cursorCol, buffer.lines[0].count)
		buffer.moveToBufferEnd()
		XCTAssertEqual(buffer.cursorRow, 1)
		XCTAssertEqual(buffer.cursorCol, buffer.lines[1].count)
		buffer.moveToBufferStart()
		XCTAssertEqual(buffer.cursorRow, 0)
		XCTAssertEqual(buffer.cursorCol, 0)
	}
	
	func testWordNavigationAcrossLines() {
		var buffer = EditorBuffer(lines: ["  foo bar", "baz quux"]) 
		buffer.moveCursorTo(row: 0, column: 0)
		buffer.moveToNextWord()
		XCTAssertEqual(buffer.cursorRow, 0)
		XCTAssertEqual(buffer.cursorCol, 2)
		buffer.moveToNextWord()
		XCTAssertEqual(buffer.cursorCol, 5) // end of "foo"
		buffer.moveToNextWord()
		XCTAssertEqual(buffer.cursorCol, 6) // start of "bar"
		buffer.moveToNextWord()
		XCTAssertEqual(buffer.cursorRow, 0)
		XCTAssertEqual(buffer.cursorCol, buffer.lines[0].count)
		buffer.moveToNextWord()
		XCTAssertEqual(buffer.cursorRow, 1)
		XCTAssertEqual(buffer.cursorCol, 3)
		buffer.moveToPreviousWord()
		XCTAssertEqual(buffer.cursorRow, 1)
		XCTAssertEqual(buffer.cursorCol, 0)
		buffer.moveToPreviousWord()
		XCTAssertEqual(buffer.cursorRow, 0)
		XCTAssertEqual(buffer.cursorCol, 6)
		buffer.moveToPreviousWord()
		XCTAssertEqual(buffer.cursorCol, 2)
		buffer.moveToPreviousWord()
		XCTAssertEqual(buffer.cursorCol, 0)
	}
	
	func testFixtureDocumentLoads() throws {
		let url = try XCTUnwrap(Bundle.module.url(forResource: "SampleDocument", withExtension: "txt"))
		let contents = try String(contentsOf: url, encoding: .utf8)
		let lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
		var buffer = EditorBuffer(lines: lines)
		buffer.moveToBufferEnd()
		XCTAssertEqual(buffer.cursorRow, max(0, lines.count - 1))
	}

	@MainActor
	func testSelectionCopyAndPaste() {
		var buffer = EditorBuffer(lines: ["let foo", "bar baz"])
		buffer.beginSelection()
		buffer.moveToNextWord(selecting: true)
		buffer.moveToNextWord(selecting: true)
		buffer.moveToNextWord(selecting: true)
		let copied = buffer.copySelection()
		XCTAssertEqual(copied, "let foo")
		_ = buffer.deleteSelection()
		XCTAssertEqual(buffer.lines[0], "")
		buffer.pasteClipboard()
		XCTAssertEqual(buffer.lines[0], "let foo")
		buffer.moveToBufferEnd()
		buffer.insert("\nqux")
		XCTAssertEqual(buffer.lines[2], "qux")
	}
}
