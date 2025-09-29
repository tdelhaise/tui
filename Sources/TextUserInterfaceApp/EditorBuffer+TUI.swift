//
//  EditorBufferTUI.swift
//  tui
//
//  Created by Thierry DELHAISE on 28/09/2025.
//

import Workspace
import Editors

extension EditorBuffer {
	public mutating func moveCursor(dRow: Int, dCol: Int) {
		let newRow = max(0, min(cursorRow + dRow, max(0, lines.count - 1)))
		let lineLen = lines.isEmpty ? 0 : lines[newRow].count
		let newCol = max(0, min(cursorCol + dCol, lineLen))
		cursorRow = newRow
		cursorCol = newCol
	}
	
	public mutating func pageScroll(page: Int, viewRows: Int) {
		let step = max(1, viewRows - 1)
		let delta = page * step
		let maxStart = max(0, lines.count - viewRows)
		scrollRow = max(0, min(scrollRow + delta, maxStart))
	}
}
