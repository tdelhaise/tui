import Foundation

public struct TUIKeymap: Sendable {
	public let quitKeys: Set<Int32>
	public let saveKeys: Set<Int32>
	public let commandPaletteKeys: Set<Int32>
	public let searchKeys: Set<Int32>
	public let searchNextKeys: Set<Int32>
	public let searchPreviousKeys: Set<Int32>
	
	public init(
		quitKeys: Set<Int32>,
		saveKeys: Set<Int32>,
		commandPaletteKeys: Set<Int32>,
		searchKeys: Set<Int32>,
		searchNextKeys: Set<Int32>,
		searchPreviousKeys: Set<Int32>
	) {
		self.quitKeys = quitKeys
		self.saveKeys = saveKeys
		self.commandPaletteKeys = commandPaletteKeys
		self.searchKeys = searchKeys
		self.searchNextKeys = searchNextKeys
		self.searchPreviousKeys = searchPreviousKeys
	}
}

public extension TUIKeymap {
	static let standard = TUIKeymap(
		quitKeys: Set<Int32>([113]), // 'q'
		saveKeys: Set<Int32>([19]), // Ctrl+S
		commandPaletteKeys: Set<Int32>([58]), // ':'
		searchKeys: Set<Int32>([47]), // '/'
		searchNextKeys: Set<Int32>([110]), // 'n'
		searchPreviousKeys: Set<Int32>([78]) // 'N'
	)
	
	static let alternate = TUIKeymap(
		quitKeys: Set<Int32>([113, 17]), // 'q', Ctrl+Q
		saveKeys: Set<Int32>([19]),
		commandPaletteKeys: Set<Int32>([58, 16]), // ':' or Ctrl+P
		searchKeys: Set<Int32>([47, 6]), // '/' or Ctrl+F
		searchNextKeys: Set<Int32>([110, 14]), // 'n' or Ctrl+N
		searchPreviousKeys: Set<Int32>([78, 2]) // 'N' or Ctrl+B
	)
}
