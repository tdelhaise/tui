import CNcursesShims

public struct TUIColorPair: Hashable, Sendable {
	public let identifier: Int16
	public let foreground: Int16
	public let background: Int16
	
	public init(identifier: Int16, foreground: Int16, background: Int16) {
		self.identifier = identifier
		self.foreground = foreground
		self.background = background
	}
}

public enum TUIThemeRole: Hashable, Sendable {
	case editorText
	case selection
	case statusBar
	case header
	case gutter
	case inspectorHeader
	case inspectorEntry
	case keyInfo
	case commandPrompt
	case searchMatch
}

public struct TUITheme: Sendable {
	public let roles: [TUIThemeRole: TUIColorPair]
	public let useDefaultBackground: Bool
	
	public init(roles: [TUIThemeRole: TUIColorPair], useDefaultBackground: Bool = true) {
		self.roles = roles
		self.useDefaultBackground = useDefaultBackground
	}
	
	public func colorPair(for role: TUIThemeRole) -> TUIColorPair? {
		roles[role]
	}
	
	@discardableResult
	public func install() -> Bool {
		let uniquePairs = Set(roles.values)
		guard !uniquePairs.isEmpty else { return false }
		for pair in uniquePairs {
			tui_init_color_pair(pair.identifier, pair.foreground, pair.background)
		}
		return true
	}
}

public extension TUITheme {
	static let `default` = TUITheme(
		roles: [
			.editorText: .init(identifier: 1, foreground: TerminalColor.white.rawValue, background: TerminalColor.black.rawValue),
			.gutter: .init(identifier: 2, foreground: TerminalColor.cyan.rawValue, background: TerminalColor.black.rawValue),
			.selection: .init(identifier: 3, foreground: TerminalColor.black.rawValue, background: TerminalColor.yellow.rawValue),
			.searchMatch: .init(identifier: 3, foreground: TerminalColor.black.rawValue, background: TerminalColor.yellow.rawValue),
			.statusBar: .init(identifier: 4, foreground: TerminalColor.black.rawValue, background: TerminalColor.green.rawValue),
			.keyInfo: .init(identifier: 5, foreground: TerminalColor.yellow.rawValue, background: TerminalColor.black.rawValue),
			.header: .init(identifier: 6, foreground: TerminalColor.yellow.rawValue, background: TerminalColor.blue.rawValue),
			.inspectorHeader: .init(identifier: 7, foreground: TerminalColor.black.rawValue, background: TerminalColor.cyan.rawValue),
			.inspectorEntry: .init(identifier: 1, foreground: TerminalColor.white.rawValue, background: TerminalColor.black.rawValue),
			.commandPrompt: .init(identifier: 8, foreground: TerminalColor.black.rawValue, background: TerminalColor.magenta.rawValue)
		]
	)

	static let highContrast = TUITheme(
		roles: [
			.editorText: .init(identifier: 1, foreground: TerminalColor.white.rawValue, background: TerminalColor.black.rawValue),
			.gutter: .init(identifier: 2, foreground: TerminalColor.yellow.rawValue, background: TerminalColor.black.rawValue),
			.selection: .init(identifier: 3, foreground: TerminalColor.black.rawValue, background: TerminalColor.white.rawValue),
			.searchMatch: .init(identifier: 3, foreground: TerminalColor.black.rawValue, background: TerminalColor.white.rawValue),
			.statusBar: .init(identifier: 4, foreground: TerminalColor.white.rawValue, background: TerminalColor.blue.rawValue),
			.keyInfo: .init(identifier: 5, foreground: TerminalColor.cyan.rawValue, background: TerminalColor.black.rawValue),
			.header: .init(identifier: 6, foreground: TerminalColor.black.rawValue, background: TerminalColor.white.rawValue),
			.inspectorHeader: .init(identifier: 7, foreground: TerminalColor.black.rawValue, background: TerminalColor.green.rawValue),
			.inspectorEntry: .init(identifier: 1, foreground: TerminalColor.white.rawValue, background: TerminalColor.black.rawValue),
			.commandPrompt: .init(identifier: 8, foreground: TerminalColor.white.rawValue, background: TerminalColor.red.rawValue)
		]
	)
}

public enum TerminalColor: Int16, Sendable {
	case black = 0
	case red = 1
	case green = 2
	case yellow = 3
	case blue = 4
	case magenta = 5
	case cyan = 6
	case white = 7
}
