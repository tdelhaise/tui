import Foundation

public struct EditorBuffer: Sendable {
	public struct Cursor: Sendable, Equatable {
		public var row: Int
		public var column: Int
		
		public init(row: Int, column: Int) {
			self.row = row
			self.column = column
		}
	}
	
	public struct Selection: Sendable, Equatable {
		public var anchor: Cursor
		public var head: Cursor
		
		public init(anchor: Cursor, head: Cursor) {
			self.anchor = anchor
			self.head = head
		}
		
		public var normalized: (start: Cursor, end: Cursor) {
			if anchor.row < head.row { return (anchor, head) }
			if anchor.row > head.row { return (head, anchor) }
			return anchor.column <= head.column ? (anchor, head) : (head, anchor)
		}
	}
	
	public var lines: [String]
	public var cursorRow: Int
	public var cursorCol: Int
	public var scrollRow: Int
	public private(set) var selection: Selection?
	public var clipboard: String
	
	public init(
		lines: [String] = [""],
		cursorRow: Int = 0,
		cursorCol: Int = 0,
		scrollRow: Int = 0,
		selection: Selection? = nil,
		clipboard: String = ""
	) {
		let sanitized = lines.isEmpty ? [""] : lines
		self.lines = sanitized
		self.cursorRow = max(0, min(cursorRow, sanitized.count - 1))
		self.cursorCol = max(0, min(cursorCol, sanitized[self.cursorRow].count))
		self.scrollRow = max(0, min(scrollRow, sanitized.count > 0 ? sanitized.count - 1 : 0))
		self.selection = selection
		self.clipboard = clipboard
	}
	
	public var cursor: Cursor {
		Cursor(row: cursorRow, column: cursorCol)
	}
	
	public var hasSelection: Bool {
		guard let selection else { return false }
		let normalized = selection.normalized
		return normalized.start != normalized.end
	}
	
	public mutating func moveCursor(byRow rowDelta: Int, column columnDelta: Int, selecting: Bool = false) {
		let previous = cursor
		let newRow = clampRow(cursorRow + rowDelta)
		let newColumn = clampColumn(column: cursorCol + columnDelta, row: newRow)
		cursorRow = newRow
		cursorCol = newColumn
		scrollRow = max(0, min(scrollRow, max(0, lines.count - 1)))
		updateSelection(from: previous, selecting: selecting)
	}
	
	public mutating func moveCursorTo(row: Int, column: Int, selecting: Bool = false) {
		let previous = cursor
		cursorRow = clampRow(row)
		cursorCol = clampColumn(column: column, row: cursorRow)
		updateSelection(from: previous, selecting: selecting)
	}
	
	public mutating func moveToLineStart(selecting: Bool = false) {
		moveCursorTo(row: cursorRow, column: 0, selecting: selecting)
	}
	
	public mutating func moveToLineEnd(selecting: Bool = false) {
		let endColumn = lines.isEmpty ? 0 : lines[cursorRow].count
		moveCursorTo(row: cursorRow, column: endColumn, selecting: selecting)
	}
	
	public mutating func moveToBufferStart(selecting: Bool = false) {
		moveCursorTo(row: 0, column: 0, selecting: selecting)
	}
	
	public mutating func moveToBufferEnd(selecting: Bool = false) {
		let lastRow = max(0, lines.count - 1)
		let lastColumn = lines.isEmpty ? 0 : lines[lastRow].count
		moveCursorTo(row: lastRow, column: lastColumn, selecting: selecting)
	}
	
	public mutating func moveToNextWord(selecting: Bool = false) {
		let destination = nextWordCursor(from: cursor)
		moveCursorTo(row: destination.row, column: destination.column, selecting: selecting)
	}
	
	public mutating func moveToPreviousWord(selecting: Bool = false) {
		let destination = previousWordCursor(from: cursor)
		moveCursorTo(row: destination.row, column: destination.column, selecting: selecting)
	}
	
	public mutating func beginSelection() {
		let current = cursor
		selection = Selection(anchor: current, head: current)
	}
	
	public mutating func clearSelection() {
		selection = nil
	}
	
	@discardableResult
	public mutating func copySelection() -> String? {
		guard let text = selectedText(), !text.isEmpty else { return nil }
		clipboard = text
		return text
	}
	
	@discardableResult
	public mutating func deleteSelection() -> Bool {
		guard hasSelection, let selection else { return false }
		let normalized = selection.normalized
		replace(from: normalized.start, to: normalized.end, with: "")
		self.selection = nil
		return true
	}
	
	public mutating func insert(_ text: String) {
		let start: Cursor
		let end: Cursor
		if let selection, hasSelection {
			let normalized = selection.normalized
			start = normalized.start
			end = normalized.end
		} else {
			start = cursor
			end = cursor
		}
		replace(from: start, to: end, with: text)
		selection = nil
	}
	
	public mutating func pasteClipboard() {
		guard !clipboard.isEmpty else { return }
		insert(clipboard)
	}
	
	public func selectedText() -> String? {
		guard let selection, hasSelection else { return nil }
		let (start, end) = selection.normalized
		if start.row == end.row {
			let line = lines[start.row]
			let startIndex = stringIndex(in: line, column: start.column)
			let endIndex = stringIndex(in: line, column: end.column)
			return String(line[startIndex..<endIndex])
		}
		var segments: [String] = []
		let firstLine = lines[start.row]
		let firstIdx = stringIndex(in: firstLine, column: start.column)
		segments.append(String(firstLine[firstIdx...]))
		if end.row - start.row > 1 {
			segments.append(contentsOf: lines[(start.row + 1)..<end.row])
		}
		let lastLine = lines[end.row]
		let lastIdx = stringIndex(in: lastLine, column: end.column)
		segments.append(String(lastLine[..<lastIdx]))
		return segments.joined(separator: "\n")
	}
	
	// MARK: - Private helpers
	
	private mutating func updateSelection(from previous: Cursor, selecting: Bool) {
		let current = cursor
		if selecting {
			if let existing = selection {
				selection = Selection(anchor: existing.anchor, head: current)
			} else {
				selection = Selection(anchor: previous, head: current)
			}
		} else {
			selection = nil
		}
	}
	
	private func clampRow(_ row: Int) -> Int {
		guard !lines.isEmpty else { return 0 }
		return max(0, min(row, lines.count - 1))
	}
	
	private func clampColumn(column: Int, row: Int) -> Int {
		guard !lines.isEmpty else { return 0 }
		let line = lines[clampRow(row)]
		return max(0, min(column, line.count))
	}
	
	private func stringIndex(in line: String, column: Int) -> String.Index {
		var offset = column
		var idx = line.startIndex
		while offset > 0, idx < line.endIndex {
			idx = line.index(after: idx)
			offset -= 1
		}
		return idx
	}
	
	private func nextWordCursor(from cursor: Cursor) -> Cursor {
		var row = clampRow(cursor.row)
		var column = clampColumn(column: cursor.column, row: row)
		while row < lines.count {
			let line = lines[row]
			let length = line.count
			if column >= length {
				if row == lines.count - 1 {
					return Cursor(row: row, column: length)
				}
				row += 1
				column = 0
				continue
			}
			if let char = character(in: line, column: column) {
				if char.isWhitespace {
					column = advance(in: line, from: column, while: { $0.isWhitespace })
					if column < length {
						return Cursor(row: row, column: column)
					}
					row += 1
					column = 0
				} else {
					column = advance(in: line, from: column, while: { !$0.isWhitespace })
					return Cursor(row: row, column: column)
				}
			} else {
				if row == lines.count - 1 {
					return Cursor(row: row, column: length)
				}
				row += 1
				column = 0
			}
		}
		return Cursor(row: max(0, lines.count - 1), column: lines.last?.count ?? 0)
	}
	
	private func previousWordCursor(from cursor: Cursor) -> Cursor {
		var row = clampRow(cursor.row)
		var column = clampColumn(column: cursor.column, row: row)
		while row >= 0 {
			if column == 0 {
				if row == 0 {
					return Cursor(row: 0, column: 0)
				}
				row -= 1
				column = lines[row].count
				continue
			}
			let line = lines[row]
			let previousIndex = column - 1
			if let char = character(in: line, column: previousIndex) {
				if char.isWhitespace {
					column = retreat(in: line, from: column, while: { $0.isWhitespace })
					if column == 0 {
						if row == 0 {
							return Cursor(row: 0, column: 0)
						}
						row -= 1
						column = lines[row].count
						continue
					}
					column = retreat(in: line, from: column, while: { !$0.isWhitespace })
					return Cursor(row: row, column: column)
				} else {
					column = retreat(in: line, from: column, while: { !$0.isWhitespace })
					return Cursor(row: row, column: column)
				}
			} else {
				return Cursor(row: row, column: column)
			}
		}
		return Cursor(row: 0, column: 0)
	}
	
	private func character(in line: String, column: Int) -> Character? {
		guard column >= 0 else { return nil }
		let col = min(column, line.count)
		if col == line.count { return nil }
		let idx = stringIndex(in: line, column: col)
		return line[idx]
	}
	
	private func advance(in line: String, from column: Int, while predicate: (Character) -> Bool) -> Int {
		var idx = stringIndex(in: line, column: column)
		var col = column
		while idx < line.endIndex {
			let char = line[idx]
			if !predicate(char) { break }
			col += 1
			idx = line.index(after: idx)
		}
		return col
	}
	
	private func retreat(in line: String, from column: Int, while predicate: (Character) -> Bool) -> Int {
		var col = column
		var idx = stringIndex(in: line, column: column)
		while col > 0 {
			let prev = line.index(before: idx)
			let char = line[prev]
			if !predicate(char) { break }
			col -= 1
			idx = prev
		}
		return col
	}
	
	private mutating func replace(from start: Cursor, to end: Cursor, with text: String) {
		let startRow = clampRow(start.row)
		let endRow = clampRow(end.row)
		let startCol = clampColumn(column: start.column, row: startRow)
		let endCol = clampColumn(column: end.column, row: endRow)
		let startLine = lines[startRow]
		let endLine = lines[endRow]
		let startIdx = stringIndex(in: startLine, column: startCol)
		let endIdx = stringIndex(in: endLine, column: endCol)
		let prefix = String(startLine[..<startIdx])
		let suffix = String(endLine[endIdx...])
		let segments = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
		var replacement = segments
		if replacement.isEmpty {
			replacement = [""]
		}
		if replacement.count == 1 {
			replacement[0] = prefix + replacement[0] + suffix
		} else {
			replacement[0] = prefix + replacement[0]
			let lastIndex = replacement.count - 1
			replacement[lastIndex] = replacement[lastIndex] + suffix
		}
		lines.replaceSubrange(startRow...endRow, with: replacement)
		if lines.isEmpty {
			lines = [""]
		}
		let insertRowOffset: Int
		let insertColumn: Int
		if segments.isEmpty {
			insertRowOffset = 0
			insertColumn = prefix.count
		} else if segments.count == 1 {
			insertRowOffset = 0
			insertColumn = prefix.count + segments[0].count
		} else {
			insertRowOffset = segments.count - 1
			insertColumn = segments.last?.count ?? 0
		}
		cursorRow = startRow + insertRowOffset
		cursorCol = clampColumn(column: insertColumn, row: cursorRow)
	}
}
