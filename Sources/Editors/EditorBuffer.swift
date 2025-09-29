// Sources/Editors/Editors.swift (ou fichier dédié)
public struct EditorBuffer: Sendable {
	public var lines: [String]
	public var cursorRow: Int
	public var cursorCol: Int
	public var scrollRow: Int
	
	public init(lines: [String] = [""],	cursorRow: Int = 0,	cursorCol: Int = 0,	scrollRow: Int = 0) {
		self.lines = lines
		self.cursorRow = cursorRow
		self.cursorCol = cursorCol
		self.scrollRow = scrollRow
	}
}
