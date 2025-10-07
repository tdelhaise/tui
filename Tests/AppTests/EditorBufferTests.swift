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

	func testInitFromTextPreservesTrailingNewline() {
		let buffer = EditorBuffer(text: "foo\nbar\n")
		XCTAssertEqual(buffer.lines, ["foo", "bar", ""])
		XCTAssertEqual(buffer.joinedLines(), "foo\nbar\n")
	}

	func testInitFromEmptyTextProvidesSingleLine() {
		let buffer = EditorBuffer(text: "")
		XCTAssertEqual(buffer.lines, [""])
		XCTAssertEqual(buffer.joinedLines(), "")
	}

	func testFindNextRespectsCaseSensitivityAndWholeWord() {
		let buffer = EditorBuffer(lines: ["Foo barbar", "foo bar"])
		let start = EditorBuffer.Cursor(row: 0, column: 0)
		let caseInsensitive = buffer.findNext(query: "foo", from: start, caseSensitive: false, wholeWord: true)
		let caseSensitive = buffer.findNext(query: "foo", from: start, caseSensitive: true, wholeWord: true)
		let partial = buffer.findNext(query: "bar", from: start, caseSensitive: true, wholeWord: true)
		XCTAssertEqual(caseInsensitive?.normalized.start.row, 0)
		XCTAssertEqual(caseInsensitive?.normalized.start.column, 0)
		XCTAssertEqual(caseSensitive?.normalized.start.row, 1)
		XCTAssertEqual(caseSensitive?.normalized.start.column, 0)
		XCTAssertEqual(partial?.normalized.start.row, 1)
		XCTAssertEqual(partial?.normalized.start.column, 4)
	}

	func testFindPreviousWrapsAroundBuffer() {
		let buffer = EditorBuffer(lines: ["alpha", "beta", "gamma alpha"])
		let start = EditorBuffer.Cursor(row: 0, column: 2)
		let previous = buffer.findPrevious(query: "alpha", from: start, caseSensitive: true, wholeWord: true)
		XCTAssertEqual(previous?.normalized.start.row, 2)
		XCTAssertEqual(previous?.normalized.start.column, 6)
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

	func testSelectionLengthHandlesUnicodeGraphemes() {
		var buffer = EditorBuffer(lines: ["🙂 café", "東京 station"])
		buffer.moveToBufferStart()
		buffer.beginSelection()
		buffer.moveToNextWord(selecting: true)
		XCTAssertEqual(buffer.selectionLength(), 1)
		buffer.moveToNextWord(selecting: true)
		XCTAssertEqual(buffer.selectionLength(), 2)
		buffer.moveToNextWord(selecting: true)
		XCTAssertEqual(buffer.selectionLength(), "🙂 café".count)
		buffer.moveCursorTo(row: 1, column: 0, selecting: true)
		buffer.moveToNextWord(selecting: true)
		let expected = "🙂 café\n東京".count
		XCTAssertEqual(buffer.selectionLength(), expected)
		let copied = buffer.copySelection()
		XCTAssertEqual(copied, "🙂 café\n東京")
	}

	func testInsertAndDeleteCharacters() {
		var buffer = EditorBuffer(lines: ["abc"])
		buffer.moveCursorTo(row: 0, column: 1)
		buffer.insertCharacter("x")
		XCTAssertEqual(buffer.lines[0], "axbc")
		buffer.insertNewline()
		XCTAssertEqual(buffer.lines, ["ax", "bc"])
		XCTAssertEqual(buffer.cursorRow, 1)
		XCTAssertEqual(buffer.cursorCol, 0)
		let backwardResult = buffer.deleteBackward()
		XCTAssertTrue(backwardResult)
		XCTAssertEqual(buffer.lines, ["axbc"])
		XCTAssertEqual(buffer.cursorRow, 0)
		XCTAssertEqual(buffer.cursorCol, 2)
		let forwardResult = buffer.deleteForward()
		XCTAssertTrue(forwardResult)
		XCTAssertEqual(buffer.lines, ["axc"])
	}
}
