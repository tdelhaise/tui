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
	
	public init(text: String) {
		let rawLines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
		self.init(lines: rawLines.isEmpty ? [text] : rawLines)
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

	public mutating func insertCharacter(_ character: Character) {
		insert(String(character))
	}

	public mutating func insertNewline() {
		insert("\n")
	}

	@discardableResult
	public mutating func deleteBackward() -> Bool {
		if deleteSelection() { return true }
		if cursorRow == 0 && cursorCol == 0 { return false }
		if cursorCol > 0 {
			let start = Cursor(row: cursorRow, column: cursorCol - 1)
			replace(from: start, to: cursor, with: "")
			return true
		}
		let previousRow = cursorRow - 1
		let previousColumn = lines[previousRow].count
		replace(from: Cursor(row: previousRow, column: previousColumn), to: cursor, with: "")
		return true
	}

	@discardableResult
	public mutating func deleteForward() -> Bool {
		if deleteSelection() { return true }
		if cursorRow >= lines.count { return false }
		let line = lines[cursorRow]
		if cursorCol < line.count {
			let next = Cursor(row: cursorRow, column: cursorCol + 1)
			replace(from: cursor, to: next, with: "")
			return true
		}
		let nextRow = cursorRow + 1
		guard nextRow < lines.count else { return false }
		replace(from: cursor, to: Cursor(row: nextRow, column: 0), with: "")
		return true
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
	
	public func selectionLength() -> Int? {
		guard let selection, hasSelection else { return nil }
		let (start, end) = selection.normalized
		if start.row == end.row {
			return end.column - start.column
		}
		var length = lines[start.row].count - start.column
		if end.row - start.row > 1 {
			for row in (start.row + 1)..<end.row {
				length += lines[row].count
			}
		}
		length += end.column
		length += (end.row - start.row)
		return length
	}

	public func joinedLines() -> String {
		if lines.isEmpty { return "" }
		return lines.joined(separator: "\n")
	}

	public func findNext(
		query: String,
		from start: Cursor,
		caseSensitive: Bool,
		wholeWord: Bool
	) -> Selection? {
		guard !query.isEmpty, !lines.isEmpty else { return nil }
		let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
		let startRow = clampRow(start.row)
		let startColumn = clampColumn(column: start.column, row: startRow)
		if let match = findNextInRows(
			query: query,
			options: options,
			rows: Array(startRow..<lines.count),
			initialColumn: startColumn,
			limitingRow: nil,
			limitingColumn: nil,
			wholeWord: wholeWord
		) {
			return match
		}
		if startRow > 0 || startColumn > 0 {
			return findNextInRows(
				query: query,
				options: options,
				rows: Array(0...startRow),
				initialColumn: 0,
				limitingRow: startRow,
				limitingColumn: startColumn,
				wholeWord: wholeWord
			)
		}
		return nil
	}

	public func findPrevious(
		query: String,
		from start: Cursor,
		caseSensitive: Bool,
		wholeWord: Bool
	) -> Selection? {
		guard !query.isEmpty, !lines.isEmpty else { return nil }
		let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
		let startRow = clampRow(start.row)
		let startColumn = clampColumn(column: start.column, row: startRow)
		let descendingRows = Array(0...startRow).reversed()
		if let match = findPreviousInRows(
			query: query,
			options: options,
			rows: Array(descendingRows),
			initialMaxColumn: startColumn,
			limitingRow: nil,
			limitingColumn: nil,
			wholeWord: wholeWord
		) {
			return match
		}
		if startRow < lines.count - 1 || startColumn < lines[startRow].count {
			let wrapRows = Array(startRow..<lines.count).reversed()
			return findPreviousInRows(
				query: query,
				options: options,
				rows: Array(wrapRows),
				initialMaxColumn: lines.last?.count ?? 0,
				limitingRow: startRow,
				limitingColumn: startColumn,
				wholeWord: wholeWord
			)
		}
		return nil
	}
	
	// MARK: - Private helpers

	private func findNextInRows(
		query: String,
		options: String.CompareOptions,
		rows: [Int],
		initialColumn: Int,
		limitingRow: Int?,
		limitingColumn: Int?,
		wholeWord: Bool
	) -> Selection? {
		for (index, row) in rows.enumerated() {
			guard row >= 0 && row < lines.count else { continue }
			let line = lines[row]
			let startColumn = index == 0 ? initialColumn : 0
			let clampedStart = clampColumn(column: startColumn, row: row)
			let startIndex = stringIndex(in: line, column: clampedStart)
			let endColumn = (limitingRow == row) ? limitingColumn : nil
			let endIndex = endColumn.map { stringIndex(in: line, column: clampColumn(column: $0, row: row)) } ?? line.endIndex
			if startIndex > endIndex { continue }
			var searchRange = startIndex..<endIndex
			while searchRange.lowerBound < searchRange.upperBound {
				guard let range = line.range(of: query, options: options, range: searchRange) else { break }
				if !wholeWord || isWholeWord(in: line, range: range) {
					let start = line.distance(from: line.startIndex, to: range.lowerBound)
					let end = line.distance(from: line.startIndex, to: range.upperBound)
					let anchor = Cursor(row: row, column: start)
					let head = Cursor(row: row, column: end)
					return Selection(anchor: anchor, head: head)
				}
				searchRange = range.upperBound..<searchRange.upperBound
			}
		}
		return nil
	}

	private func findPreviousInRows(
		query: String,
		options: String.CompareOptions,
		rows: [Int],
		initialMaxColumn: Int,
		limitingRow: Int?,
		limitingColumn: Int?,
		wholeWord: Bool
	) -> Selection? {
		for (index, row) in rows.enumerated() {
			guard row >= 0 && row < lines.count else { continue }
			let line = lines[row]
			let defaultMax = line.count
			let maxColumn: Int
			if index == 0 {
				maxColumn = clampColumn(column: initialMaxColumn, row: row)
			} else if let limitingRow, limitingRow == row {
				maxColumn = clampColumn(column: limitingColumn ?? defaultMax, row: row)
			} else {
				maxColumn = defaultMax
			}
			guard maxColumn > 0 else { continue }
			let endIndex = stringIndex(in: line, column: maxColumn)
			let matchRange = findPreviousMatch(in: line, query: query, options: options, endIndex: endIndex, wholeWord: wholeWord)
			if let range = matchRange {
				let start = line.distance(from: line.startIndex, to: range.lowerBound)
				let end = line.distance(from: line.startIndex, to: range.upperBound)
				let anchor = Cursor(row: row, column: start)
				let head = Cursor(row: row, column: end)
				return Selection(anchor: anchor, head: head)
			}
		}
		return nil
	}

	private func findPreviousMatch(
		in line: String,
		query: String,
		options: String.CompareOptions,
		endIndex: String.Index,
		wholeWord: Bool
	) -> Range<String.Index>? {
		var searchRange = line.startIndex..<endIndex
		var candidate: Range<String.Index>? = nil
		while searchRange.lowerBound < searchRange.upperBound {
			guard let range = line.range(of: query, options: options, range: searchRange) else { break }
			if !wholeWord || isWholeWord(in: line, range: range) {
				candidate = range
			}
			if range.lowerBound <= searchRange.lowerBound { break }
			searchRange = searchRange.lowerBound..<range.lowerBound
		}
		return candidate
	}

	private func isWholeWord(in line: String, range: Range<String.Index>) -> Bool {
		if range.lowerBound > line.startIndex {
			let beforeIndex = line.index(before: range.lowerBound)
			if isWordCharacter(line[beforeIndex]) { return false }
		}
		if range.upperBound < line.endIndex {
			let afterChar = line[range.upperBound]
			if isWordCharacter(afterChar) { return false }
		}
		return true
	}

	private func isWordCharacter(_ character: Character) -> Bool {
		character.isLetter || character.isNumber || character == "_"
	}

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
