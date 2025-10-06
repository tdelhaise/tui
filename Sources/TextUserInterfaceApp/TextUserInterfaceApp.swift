import Foundation
import CNcursesShims
import Utilities
import Workspace
import Editors
import Logging


public protocol DiagnosticsProvider: AnyObject {
	func currentDiagnostics() -> [Diagnostic]
}

public enum TUIKeys : Int32 {
	case EscapeKey = 27,
		 MinusQKey = 123
}

@MainActor
public final class TextUserInterfaceApp {
	
	private let logger: Logger
	private let theme: TUITheme
	private let keymap: TUIKeymap
	private var buffer: EditorBuffer?      // ⬅️ conserver l’état
	private struct KeyInspectorEntry {
		var rawLabel: String
		var asciiLabel: String
		var note: String
	}

	private struct KeyInspectorState {
		var isEnabled: Bool
		var entries: [KeyInspectorEntry]
	}

	private struct SearchConfiguration: Equatable {
		var query: String
		var caseSensitive: Bool
		var wholeWord: Bool
	}

	private struct SearchModeState {
		var origin: EditorBuffer.Cursor
		var config: SearchConfiguration
	}

	private struct CommandPaletteState {
		var query: String
	}

	private struct CommandExecutionResult {
		var success: Bool
		var inspectorNote: String?
	}

	private enum InputMode {
		case normal
		case search(SearchModeState)
		case commandPalette(CommandPaletteState)
	}

	private enum SearchDirection {
		case forward
		case backward
	}

	private enum KeyHandlerOutcome {
		case unhandled
		case handled(inspectorNote: String?)
	}

	struct LayoutMetrics {
		var cols: Int32
		var rows: Int32
		var editorTop: Int32
		var editorHeight: Int32
		var gutterWidth: Int32
		var inspectorTop: Int32?
		var inspectorHeight: Int32
		var diagnosticsTop: Int32?
		var diagnosticsHeight: Int32
		var keyInfoRow: Int32
		var footerRow: Int32
	}

	private let inspectorCapacity = 6
	private let inspectorPanelHeight: Int32 = 8
	private var keyInspector: KeyInspectorState
	private var documentURL: URL?
	private var isDirty: Bool = false
	private var startupStatusMessage: String?
	private var inputMode: InputMode = .normal
	private var lastSearch: SearchConfiguration?
	private var lastSearchDirection: SearchDirection = .forward
	private var navigationBack: [EditorBuffer.Cursor] = []
	private var navigationForward: [EditorBuffer.Cursor] = []
	private let navigationHistoryLimit = 128
	private var suppressHistoryRecording = false
	private var colorsEnabled = false

	// éventuellement:
	private weak var diagsProvider: DiagnosticsProvider?
	private var statusMessage: String = ""

	public init(theme: TUITheme = .default, keymap: TUIKeymap = .standard, enableKeyInspector: Bool = false) {
		var log = Logger(label: "TextUserInterfaceApp")
		log.logLevel = Self.resolveLogLevel()
		self.logger = log
		self.theme = theme
		self.keymap = keymap
		self.keyInspector = KeyInspectorState(isEnabled: enableKeyInspector, entries: [])
	}
	
	private static func resolveLogLevel() -> Logger.Level {
		guard let raw = ProcessInfo.processInfo.environment["TUI_LOG_LEVEL"],
				let level = Logger.Level(envValue: raw) else {
			return .info
		}
		return level
	}

	private func configureColors() {
		colorsEnabled = false
		guard tui_has_colors() else { return }
		tui_start_color()
		if theme.useDefaultBackground {
			tui_use_default_colors()
		}
		colorsEnabled = theme.install()
	}

	private func colorPair(for role: TUIThemeRole) -> TUIColorPair? {
		if let pair = theme.colorPair(for: role) {
			return pair
		}
		return theme.colorPair(for: .editorText)
	}

	private func makeLayout(rows: Int32, cols: Int32, inspectorHeight: Int32, diagnosticsHeight: Int32, buffer: EditorBuffer?) -> LayoutMetrics {
		let footerRow = max(0, rows - 1)
		let keyInfoRow = max(0, footerRow - 1)
		let reservedTop: Int32 = 2
		let inspectorClamped = max(0, inspectorHeight)
		let diagnosticsClamped = max(0, diagnosticsHeight)
		var nextTop = keyInfoRow
		let inspectorTop: Int32?
		if inspectorClamped > 0 {
			let top = max(reservedTop, nextTop - inspectorClamped)
			inspectorTop = top
			nextTop = top
		} else {
			inspectorTop = nil
		}
		let diagnosticsTop: Int32?
		if diagnosticsClamped > 0 {
			let top = max(reservedTop, nextTop - diagnosticsClamped)
			diagnosticsTop = top
			nextTop = top
		} else {
			diagnosticsTop = nil
		}
		let editorTop = reservedTop
		var editorHeight = nextTop - editorTop
		if editorHeight < 3 {
			let fallback = rows - reservedTop - max(0, footerRow - keyInfoRow) - inspectorClamped - diagnosticsClamped
			editorHeight = max(3, fallback)
		}
		let desiredGutter = gutterWidth(for: buffer)
		let gutterLimit = max(Int32(0), cols - 10)
		let gutterWidth = gutterLimit > 0 ? min(desiredGutter, gutterLimit) : 0
		return LayoutMetrics(
			cols: cols,
			rows: rows,
			editorTop: editorTop,
			editorHeight: max(3, editorHeight),
			gutterWidth: gutterWidth,
			inspectorTop: inspectorTop,
			inspectorHeight: inspectorClamped,
			diagnosticsTop: diagnosticsTop,
			diagnosticsHeight: diagnosticsClamped,
			keyInfoRow: keyInfoRow,
			footerRow: footerRow
		)
	}

	private func gutterWidth(for buffer: EditorBuffer?) -> Int32 {
		let count = max(1, buffer?.lines.count ?? 1)
		let digits = max(2, String(count).count)
		return Int32(max(4, digits + 2))
	}
	
	public func run(
		buffer: EditorBuffer?,
		documentURL: URL? = nil,
		diagsProvider: DiagnosticsProvider?,
		enableKeyInspector: Bool = false,
		startupStatus: String? = nil
	) {
		self.buffer = buffer ?? EditorBuffer()
		self.documentURL = documentURL
		self.isDirty = false
		self.inputMode = .normal
		self.lastSearch = nil
		self.lastSearchDirection = .forward
		navigationBack.removeAll(keepingCapacity: true)
		navigationForward.removeAll(keepingCapacity: true)
		self.diagsProvider = diagsProvider
		keyInspector.isEnabled = enableKeyInspector
		keyInspector.entries.removeAll(keepingCapacity: true)
		startupStatusMessage = startupStatus
		
		initscr()
		defer { endwin() }
		configureColors()

		cbreak()
		noecho() // n’affiche pas automatiquement les touches
		nonl() // no new line
		tui_intr_flush(true)
		
		raw() // capture aussi Ctrl+C, Ctrl+Z, etc.
		tui_keypad_stdscr(true) // wrapper C : on active keypad(stdscr, TRUE), active les KEY_*
		
		setlocale(LC_ALL, "")
		
#if os(Linux)
		// Si tu veux la souris Linux: _ = mousemask(mmask_t(~0), nil)
#endif
		
		var diagHeight: Int32 = 8
		var running = true
		
		if let startupStatusMessage {
			statusMessage = startupStatusMessage
			self.startupStatusMessage = nil
		}
		while running {
			erase()
			
			let cols: Int32 = Int32(tui_cols())
			let rows: Int32 = Int32(tui_lines())
			let inspectorHeight: Int32 = keyInspector.isEnabled ? inspectorPanelHeight : 0
			let diagnosticsHeight: Int32 = (diagsProvider != nil) ? diagHeight : 0
			let layout = makeLayout(rows: rows, cols: cols, inspectorHeight: inspectorHeight, diagnosticsHeight: diagnosticsHeight, buffer: buffer)
			let header = headerLine(maxWidth: Int(cols))
			putCleared(0, 0, header, role: .header)
			mvhline(1, 0, 0, cols)
			if let buf = buffer {
				renderEditor(buf: buf, layout: layout)
			} else {
				put(3, 2, "No file open. Use --file <path> to open a file.")
			}
			if let provider = diagsProvider, layout.diagnosticsHeight > 0, let top = layout.diagnosticsTop {
				drawDiagnostics(provider: provider, top: top, height: layout.diagnosticsHeight, width: cols)
			}
			if layout.inspectorHeight > 0, let inspectorTop = layout.inspectorTop {
				renderKeyInspector(top: inspectorTop, height: layout.inspectorHeight, width: cols)
			}
			
			refresh()
			let ch = getch()
			let key = Int32(ch)
			let hexString = String(format:"%08X", key)
			let asciiSummary = asciiLabel(for: key)
			var inspectorNote: String? = nil
			switch handleSearchInput(key: key, ascii: asciiSummary) {
			case .handled(let note):
				if let note { inspectorNote = note }
				if let noteToRecord = inspectorNote ?? note {
					recordKeyInspector(key: key, ascii: asciiSummary, note: noteToRecord)
				}
				continue
			case .unhandled:
				break
			}
			switch handleCommandPaletteInput(key: key, ascii: asciiSummary) {
			case .handled(let note):
				if let note { inspectorNote = note }
				if let noteToRecord = inspectorNote ?? note {
					recordKeyInspector(key: key, ascii: asciiSummary, note: noteToRecord)
				}
				continue
			case .unhandled:
				break
			}
			
			let viewRows = max(1, Int(layout.editorHeight))
			switch key {
			case let value where keymap.quitKeys.contains(value):
				logger.info("key: \(hexString) aka \(key) -> quit hotkey")
				inspectorNote = "quit"
				running = false
			case let value where keymap.saveKeys.contains(value):
				logger.info("key: \(hexString) aka \(key) -> save hotkey")
				inspectorNote = "save"
				let saved = saveDocument()
				notifySaveOutcome(success: saved)
			case 27:
				if handleEscapeSequence() {
					continue
				}
				logger.info("key: \(hexString) aka \(key)")
				inspectorNote = "escape"
			case KEY_UP:
				logger.info("key: \(hexString) aka \(key) aka KEY_UP")
				inspectorNote = "cursor up"
				mutateBuffer { buffer in
					buffer.moveCursor(dRow: -1, dCol: 0)
					return nil
				}
			case KEY_DOWN:
				logger.info("key: \(hexString) aka \(key) aka KEY_DOWN")
				mutateBuffer { buffer in
					buffer.moveCursor(dRow: 1, dCol: 0)
					return nil
				}
			case KEY_LEFT:
				logger.info("key: \(hexString) aka \(key) aka KEY_LEFT")
				mutateBuffer { buffer in
					buffer.moveCursor(dRow: 0, dCol: -1)
					return nil
				}
			case KEY_RIGHT:
				logger.info("key: \(hexString) aka \(key) aka KEY_RIGHT")
				mutateBuffer { buffer in
					buffer.moveCursor(dRow: 0, dCol: 1)
					return nil
				}
			case KEY_SLEFT:
				logger.info("key: \(hexString) aka \(key) aka KEY_SLEFT")
				inspectorNote = "select left"
				mutateBuffer { buffer in
					buffer.moveCursor(dRow: 0, dCol: -1, selecting: true)
					return nil
				}
			case KEY_SRIGHT:
				logger.info("key: \(hexString) aka \(key) aka KEY_SRIGHT")
				inspectorNote = "select right"
				mutateBuffer { buffer in
					buffer.moveCursor(dRow: 0, dCol: 1, selecting: true)
					return nil
				}
			case KEY_HOME:
				logger.info("key: \(hexString) aka \(key) aka KEY_HOME")
				mutateBuffer { buffer in
					buffer.moveToLineStart()
					return nil
				}
			case KEY_END:
				logger.info("key: \(hexString) aka \(key) aka KEY_END")
				mutateBuffer { buffer in
					buffer.moveToLineEnd()
					return nil
				}
			case KEY_SHOME:
				logger.info("key: \(hexString) aka \(key) aka KEY_SHOME")
				inspectorNote = "select line start"
				mutateBuffer { buffer in
					buffer.moveToLineStart(selecting: true)
					return nil
				}
			case KEY_SEND:
				logger.info("key: \(hexString) aka \(key) aka KEY_SEND")
				inspectorNote = "select line end"
				mutateBuffer { buffer in
					buffer.moveToLineEnd(selecting: true)
					return nil
				}
			case KEY_NPAGE:
				logger.info("key: \(hexString) aka \(key) aka KEY_NPAGE")
				inspectorNote = "page down"
				mutateBuffer { buffer in
					buffer.pageScroll(page: +1, viewRows: viewRows)
					return nil
				}
			case KEY_PPAGE:
				logger.info("key: \(hexString) aka \(key) aka KEY_PPAGE")
				inspectorNote = "page up"
				mutateBuffer { buffer in
					buffer.pageScroll(page: -1, viewRows: viewRows)
					return nil
				}
			case 100:
				logger.info("key: \(hexString) aka \(key) aka ???")
				inspectorNote = "toggle diagnostics"
				diagHeight = (diagHeight == 0) ? 8 : 0
			case 112, 80:
				logger.info("key: \(hexString) aka \(key) aka 112,80")
				inspectorNote = "paste clipboard"
				mutateBuffer { buffer in
					guard !buffer.clipboard.isEmpty else { return "Clipboard empty" }
					buffer.pasteClipboard()
					notify(title: "Clipboard Pasted", message: summarize(buffer.clipboard), kind: .success, metadata: ["length": String(buffer.clipboard.count)])
					return "Pasted \\(buffer.clipboard.count) chars"
				}
			case 118, 86:
				logger.info("key: \(hexString) aka \(key) aka 118,86")
				inspectorNote = "toggle selection anchor"
				mutateBuffer { buffer in
					if buffer.hasSelection {
						buffer.clearSelection()
						return "Selection cleared"
					} else {
						buffer.beginSelection()
						return "Selection anchor set"
					}
				}
			case 120, 88:
				logger.info("key: \(hexString) aka \(key) aka 120,88")
				inspectorNote = "cut selection"
				mutateBuffer { buffer in
					guard let copied = buffer.copySelection(), !copied.isEmpty else { return "No selection to cut" }
					_ = buffer.deleteSelection()
					let preview = summarize(copied)
					notify(title: "Selection Cut", message: preview, kind: .warning, metadata: ["length": String(copied.count)])
					return "Cut \\(copied.count) chars"
				}
			case 121, 89:
				logger.info("key: \(hexString) aka \(key) aka 121,89")
				inspectorNote = "copy selection"
				mutateBuffer { buffer in
					guard let copied = buffer.copySelection(), !copied.isEmpty else { return "No selection to copy" }
					let preview = summarize(copied)
					notify(title: "Selection Copied", message: preview, kind: .info, metadata: ["length": String(copied.count)])
					return "Copied \\(copied.count) chars"
				}
			case KEY_F0+6:
				logger.info("key: \(hexString) aka \(key) aka KEY_F7")
				if navigateBack() {
					inspectorNote = "nav back"
				}
			case KEY_F0+7:
				logger.info("key: \(hexString) aka \(key) aka KEY_F8")
				if navigateForward() {
					inspectorNote = "nav forward"
				}
			default:
				logger.info("key: \(hexString) aka \(key)")
			}
		if let note = inspectorNote {
			recordKeyInspector(key: key, ascii: asciiSummary, note: note)
		}

			let keyInfo = "key: \(ch)"
			putCleared(layout.keyInfoRow, 2, keyInfo, role: .keyInfo)
			var footerParts: [String] = [documentDisplayName()]
			if let buf = buffer {
				var cursorInfo = "pos \(buf.cursorRow + 1):\(buf.cursorCol + 1)"
				if let selectionLength = buf.selectionLength() {
					cursorInfo += "  sel=\(selectionLength)"
				}
				footerParts.append(cursorInfo)
			}
			if let searchSummary = searchPromptFooter() {
				footerParts.append(searchSummary)
			}
			if let paletteSummary = commandPaletteFooter() {
				footerParts.append(paletteSummary)
			}
			footerParts.append("q/ESC to quit")
			if !statusMessage.isEmpty {
				footerParts.append(statusMessage)
			}
			let footer = footerParts.joined(separator: "  ")
			let footerWidth = max(0, Int(layout.cols) - 4)
			putCleared(layout.footerRow, 2, TextWidth.clip(footer, max: footerWidth), role: .statusBar)
			statusMessage = ""
		}
	}
	
	private func mutateBuffer(_ body: (inout EditorBuffer) -> String?) {
		guard var buf = buffer else { return }
		let previousLines = buf.lines
		let message = body(&buf)
		let linesChanged = buf.lines != previousLines
		buffer = buf
		if linesChanged {
			isDirty = true
		}
		if let message {
			statusMessage = message
		}
	}

	private func handleSearchInput(key: Int32, ascii: String) -> KeyHandlerOutcome {
		switch inputMode {
		case .search(var state):
			var inspector: String? = nil
			var stateChanged = false
			switch key {
			case 27:
				cancelSearch(state: state)
				return .handled(inspectorNote: "search cancel")
			case KEY_ENTER, 10, 13:
				if commitSearch(state: state) {
					return .handled(inspectorNote: "search commit")
				} else {
					inspector = "search no match"
				}
			case KEY_BACKSPACE, 127, 8:
				if !state.config.query.isEmpty {
					state.config.query.removeLast()
					stateChanged = true
				}
				updateSearchPreview(for: &state)
				inspector = "search backspace"
			case 20: // Ctrl+T toggle case sensitivity
				state.config.caseSensitive.toggle()
				stateChanged = true
				updateSearchPreview(for: &state)
				inspector = state.config.caseSensitive ? "search case:on" : "search case:off"
			case 23: // Ctrl+W toggle whole word
				state.config.wholeWord.toggle()
				stateChanged = true
				updateSearchPreview(for: &state)
				inspector = state.config.wholeWord ? "search word:on" : "search word:off"
			default:
				if key >= 32 && key < 127, let scalar = UnicodeScalar(Int(key)) {
					state.config.query.append(Character(scalar))
					stateChanged = true
					updateSearchPreview(for: &state)
					inspector = "search append"
				} else {
					return .handled(inspectorNote: nil)
				}
			}
			if stateChanged {
				inputMode = .search(state)
			}
			return .handled(inspectorNote: inspector)
		case .normal:
			if keymap.searchKeys.contains(key) {
				enterSearchMode()
				return .handled(inspectorNote: "search mode")
			}
			if keymap.searchNextKeys.contains(key) {
				let success = repeatSearch(.forward)
				return .handled(inspectorNote: success ? "search next" : "search next missing")
			}
			if keymap.searchPreviousKeys.contains(key) {
				let success = repeatSearch(.backward)
				return .handled(inspectorNote: success ? "search previous" : "search previous missing")
			}
			return .unhandled
		case .commandPalette:
			return .unhandled
		}
	}

	private func enterSearchMode() {
		let origin = buffer?.cursor ?? EditorBuffer.Cursor(row: 0, column: 0)
		let reuse = lastSearch ?? SearchConfiguration(query: "", caseSensitive: false, wholeWord: false)
		var state = SearchModeState(origin: origin, config: reuse)
		inputMode = .search(state)
		updateSearchPreview(for: &state)
		inputMode = .search(state)
		statusMessage = "Search: Enter=jump Esc=cancel Ctrl+T=case Ctrl+W=word"
	}

	private func handleCommandPaletteInput(key: Int32, ascii: String) -> KeyHandlerOutcome {
		switch inputMode {
		case .commandPalette(var state):
			var note: String? = nil
			var stateChanged = false
			switch key {
			case 27:
				inputMode = .normal
				statusMessage = "Command palette closed"
				note = "palette cancel"
			case KEY_ENTER, 10, 13:
				let result = executeCommand(query: state.query)
				inputMode = .normal
				note = result.inspectorNote ?? (result.success ? "palette run" : "palette error")
			case KEY_BACKSPACE, 127, 8:
				if !state.query.isEmpty {
					state.query.removeLast()
					stateChanged = true
				}
				note = "palette backspace"
			default:
				if key >= 32 && key < 127, let scalar = UnicodeScalar(Int(key)) {
					state.query.append(Character(scalar))
					stateChanged = true
					note = "palette append"
				} else {
					note = nil
				}
			}
			if stateChanged {
				inputMode = .commandPalette(state)
			}
			return .handled(inspectorNote: note)
		case .normal:
			if keymap.commandPaletteKeys.contains(key) {
				openCommandPalette()
				return .handled(inspectorNote: "palette open")
			}
			return .unhandled
		case .search:
			return .unhandled
		}
	}

	private func executeCommand(query: String) -> CommandExecutionResult {
		let trimmed = query.trimmingCharacters(in: .whitespaces)
		guard !trimmed.isEmpty else {
			statusMessage = "No command provided"
			return CommandExecutionResult(success: false, inspectorNote: "palette empty")
		}
		let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
		guard let rawCommand = parts.first else {
			statusMessage = "No command provided"
			return CommandExecutionResult(success: false, inspectorNote: "palette empty")
		}
		var command = rawCommand.lowercased()
		if command.hasSuffix("!") {
			command.removeLast()
		}
		switch command {
		case "write", "w":
			let argument = parts.count > 1 ? String(parts[1]) : nil
			return executeWriteCommand(pathArgument: argument)
		default:
			statusMessage = "Unknown command: \(command)"
			return CommandExecutionResult(success: false, inspectorNote: "palette unknown")
		}
	}

	private func executeWriteCommand(pathArgument: String?) -> CommandExecutionResult {
		guard let currentBuffer = buffer else {
			statusMessage = "No buffer to save"
			return CommandExecutionResult(success: false, inspectorNote: "palette write failed")
		}
		let success: Bool
		if let pathArgument, !pathArgument.trimmingCharacters(in: .whitespaces).isEmpty {
			let targetURL = expandedURL(from: pathArgument)
			success = writeBuffer(currentBuffer, to: targetURL, updateDocumentURL: true)
		} else {
			success = saveDocument()
		}
		notifySaveOutcome(success: success)
		return CommandExecutionResult(success: success, inspectorNote: success ? "palette write" : "palette write failed")
	}

	private func openCommandPalette() {
		inputMode = .commandPalette(CommandPaletteState(query: ""))
		statusMessage = "Command palette. Enter=run Esc=cancel"
	}

	private func updateSearchPreview(for state: inout SearchModeState) {
		guard let buf = buffer else { return }
		if state.config.query.isEmpty {
			mutateBuffer { buffer in
				buffer.moveCursorTo(row: state.origin.row, column: state.origin.column)
				buffer.clearSelection()
				return nil
			}
			return
		}
		if let match = buf.findNext(
			query: state.config.query,
			from: state.origin,
			caseSensitive: state.config.caseSensitive,
			wholeWord: state.config.wholeWord
		) {
			applySelection(match)
		} else {
			mutateBuffer { buffer in
				buffer.moveCursorTo(row: state.origin.row, column: state.origin.column)
				buffer.clearSelection()
				return nil
			}
			statusMessage = "No match for \"\(state.config.query)\""
		}
	}

	private func commitSearch(state: SearchModeState) -> Bool {
		let success = executeSearch(
			direction: .forward,
			config: state.config,
			start: state.origin,
			recordOrigin: state.origin,
			setLastSearch: true
		)
		if success {
			inputMode = .normal
		}
		return success
	}

	private func cancelSearch(state: SearchModeState) {
		mutateBuffer { buffer in
			buffer.moveCursorTo(row: state.origin.row, column: state.origin.column)
			buffer.clearSelection()
			return "Search cancelled"
		}
		inputMode = .normal
	}

	private func repeatSearch(_ direction: SearchDirection) -> Bool {
		guard let config = lastSearch else {
			statusMessage = "No previous search"
			return false
		}
		guard let current = buffer?.cursor else { return false }
		let start = searchStartCursor(for: direction, config: config)
		let success = executeSearch(
			direction: direction,
			config: config,
			start: start,
			recordOrigin: current,
			setLastSearch: false
		)
		return success
	}

	@discardableResult
	private func executeSearch(
		direction: SearchDirection,
		config: SearchConfiguration,
		start: EditorBuffer.Cursor,
		recordOrigin: EditorBuffer.Cursor?,
		setLastSearch: Bool
	) -> Bool {
		guard let buf = buffer else { return false }
		let selection: EditorBuffer.Selection?
		switch direction {
		case .forward:
			selection = buf.findNext(
				query: config.query,
				from: start,
				caseSensitive: config.caseSensitive,
				wholeWord: config.wholeWord
			)
		case .backward:
			selection = buf.findPrevious(
				query: config.query,
				from: start,
				caseSensitive: config.caseSensitive,
				wholeWord: config.wholeWord
			)
		}
		guard let match = selection else {
			statusMessage = "No match for \"\(config.query)\""
			return false
		}
		if let origin = recordOrigin {
			recordNavigationSnapshot(origin)
		}
		applySelection(match)
		statusMessage = "Match for \"\(config.query)\""
		lastSearchDirection = direction
		if setLastSearch {
			lastSearch = config
		}
		return true
	}

	private func recordNavigationSnapshot(_ cursor: EditorBuffer.Cursor) {
		if let last = navigationBack.last, last == cursor { return }
		navigationBack.append(cursor)
		if navigationBack.count > navigationHistoryLimit {
			navigationBack.removeFirst(navigationBack.count - navigationHistoryLimit)
		}
		navigationForward.removeAll(keepingCapacity: true)
	}

	private func applySelection(_ selection: EditorBuffer.Selection) {
		let normalized = selection.normalized
		mutateBuffer { buffer in
			buffer.moveCursorTo(row: normalized.start.row, column: normalized.start.column)
			buffer.beginSelection()
			buffer.moveCursorTo(row: normalized.end.row, column: normalized.end.column, selecting: true)
			return nil
		}
	}

	private func searchPromptFooter() -> String? {
		guard case .search(let state) = inputMode else { return nil }
		let queryDisplay = state.config.query.isEmpty ? "<empty>" : state.config.query
		let caseIndicator = state.config.caseSensitive ? "Aa:on" : "Aa:off"
		let wordIndicator = state.config.wholeWord ? "W:on" : "W:off"
		return "/\(queryDisplay)  \(caseIndicator)  \(wordIndicator)  Enter:jump Esc:cancel Ctrl+T:case Ctrl+W:word"
	}

	private func commandPaletteFooter() -> String? {
		guard case .commandPalette(let state) = inputMode else { return nil }
		let display = state.query.isEmpty ? "<type to filter>" : state.query
		return ": \(display)  Enter:run Esc:cancel"
	}

	private func currentSelectionMatches(_ config: SearchConfiguration) -> Bool {
		guard let selected = buffer?.selectedText(), !selected.isEmpty else { return false }
		if config.caseSensitive {
			return selected == config.query
		}
		return selected.compare(config.query, options: .caseInsensitive) == .orderedSame
	}

	private func searchStartCursor(for direction: SearchDirection, config: SearchConfiguration) -> EditorBuffer.Cursor {
		guard let buf = buffer else { return EditorBuffer.Cursor(row: 0, column: 0) }
		if currentSelectionMatches(config), let selection = buf.selection?.normalized {
			switch direction {
			case .forward:
				return selection.end
			case .backward:
				return selection.start
			}
		}
		return buf.cursor
	}

	private func navigateBack() -> Bool {
		guard let destination = navigationBack.popLast() else {
			statusMessage = "No earlier location"
			return false
		}
		guard let current = buffer?.cursor else { return false }
		navigationForward.append(current)
		if navigationForward.count > navigationHistoryLimit {
			navigationForward.removeFirst(navigationForward.count - navigationHistoryLimit)
		}
		mutateBuffer { buffer in
			buffer.clearSelection()
			buffer.moveCursorTo(row: destination.row, column: destination.column)
			return "History back \(destination.row + 1):\(destination.column + 1)"
		}
		return true
	}

	private func navigateForward() -> Bool {
		guard let destination = navigationForward.popLast() else {
			statusMessage = "No forward location"
			return false
		}
		if let current = buffer?.cursor {
			navigationBack.append(current)
			if navigationBack.count > navigationHistoryLimit {
				navigationBack.removeFirst(navigationBack.count - navigationHistoryLimit)
			}
		}
		mutateBuffer { buffer in
			buffer.clearSelection()
			buffer.moveCursorTo(row: destination.row, column: destination.column)
			return "History forward \(destination.row + 1):\(destination.column + 1)"
		}
		return true
	}

	private func recordKeyInspector(key: Int32, ascii: String, note: String) {
		guard keyInspector.isEnabled else { return }
		let rawLabel = String(format: "%X", Int(key))
		appendInspectorEntry(raw: rawLabel, ascii: ascii, note: note)
	}

	private func recordKeyInspector(sequence codes: [Int32], ascii: String, note: String) {
		guard keyInspector.isEnabled else { return }
		let components = codes.map { String(format: "%X", Int($0)) }
		let rawLabel = components.joined(separator: " ")
		appendInspectorEntry(raw: rawLabel, ascii: ascii, note: note)
	}

	private func appendInspectorEntry(raw: String, ascii: String, note: String) {
		var asciiLabel = ascii
		if asciiLabel.isEmpty { asciiLabel = "-" }
		let entry = KeyInspectorEntry(rawLabel: raw, asciiLabel: asciiLabel, note: note)
		keyInspector.entries.append(entry)
		if keyInspector.entries.count > inspectorCapacity {
			keyInspector.entries.removeFirst(keyInspector.entries.count - inspectorCapacity)
		}
	}

	private func asciiLabel(for key: Int32) -> String {
		if key >= 32 && key < 127, let scalar = UnicodeScalar(UInt32(key)) {
			return "'\(Character(scalar))'"
		}
		return "-"
	}

	private func renderKeyInspector(top: Int32, height: Int32, width: Int32) {
		guard keyInspector.isEnabled, height > 1 else { return }
		mvhline(top, 0, 0, width)
		let header = "Key Inspector"
		putCleared(top + 1, 1, TextWidth.clip(header, max: Int(width) - 2), role: .inspectorHeader)
		let availableRows = max(0, Int(height) - 2)
		guard availableRows > 0 else { return }
		let recent = keyInspector.entries.suffix(availableRows)
		var row = top + 2
		for entry in recent.reversed() {
			let line = "\(entry.rawLabel)  \(entry.asciiLabel)  \(entry.note)"
			putCleared(row, 1, TextWidth.clip(line, max: Int(width) - 2), role: .inspectorEntry)
			row += 1
		}
		while row < top + height {
			putCleared(row, 1, "")
			row += 1
		}
	}

	private func notify(title: String, message: String, kind: NotificationPayload.Kind, metadata: [String: String] = [:]) {
		NotificationServices.shared().post(.init(title: title, message: message, kind: kind, metadata: metadata))
	}

	private func summarize(_ text: String, limit: Int = 64) -> String {
		if text.count <= limit { return text }
		let prefix = text.prefix(limit)
		return String(prefix) + "..."
	}

	private func headerLine(maxWidth: Int) -> String {
		guard maxWidth > 0 else { return "" }
		let docName = documentDisplayName()
		let shortcuts = "  Ctrl+S:save  /:search  :palette  n/N:repeat  F7/F8:nav  q/ESC:quit  arrows:move  Shift+arrows:select  Home/End  PgUp/PgDn  v:select  y:copy  x:cut  p:paste  d:diag"
		let header = "tui — \(docName)\(shortcuts)"
		return TextWidth.clip(header, max: maxWidth)
	}

	private func documentDisplayName() -> String {
		let base = documentURL?.lastPathComponent ?? "untitled"
		return isDirty ? base + "*" : base
	}

	private func saveDocument() -> Bool {
		guard let currentBuffer = buffer else {
			statusMessage = "No buffer to save"
			return false
		}
		guard let url = documentURL else {
			statusMessage = "Use :write <path> to pick a save location"
			return false
		}
		return writeBuffer(currentBuffer, to: url, updateDocumentURL: false)
	}

	private func writeBuffer(_ buffer: EditorBuffer, to url: URL, updateDocumentURL: Bool) -> Bool {
		do {
			let text = buffer.joinedLines()
			try text.write(to: url, atomically: true, encoding: .utf8)
			if updateDocumentURL {
				documentURL = url
			}
			isDirty = false
			statusMessage = "Saved \(url.lastPathComponent)"
			return true
		} catch {
			statusMessage = "Save failed: \(error.localizedDescription)"
			return false
		}
	}

	private func notifySaveOutcome(success: Bool) {
		if success {
			notify(title: "File Saved", message: documentDisplayName(), kind: .success, metadata: saveMetadata())
		} else {
			notify(title: "Save Failed", message: statusMessage, kind: .warning, metadata: saveMetadata())
		}
	}

	private func expandedURL(from path: String) -> URL {
		let expanded = NSString(string: path).expandingTildeInPath
		return URL(fileURLWithPath: expanded)
	}

	private func saveMetadata() -> [String: String] {
		var metadata: [String: String] = ["dirty": isDirty ? "true" : "false"]
		if let url = documentURL {
			metadata["path"] = url.path
		}
		return metadata
	}

	private func putCleared(_ y: Int32, _ x: Int32, _ s: String, role: TUIThemeRole = .editorText) {
		move(y, x)
		clrtoeol()
		put(y, x, s, role: role)
	}

	// Helpers non-variadiques
	private func put(_ y: Int32, _ x: Int32, _ s: String, role: TUIThemeRole = .editorText) {
		move(y, x)
		append(s, role: role)
	}
	
	private func append(_ s: String, role: TUIThemeRole = .editorText) {
		guard !s.isEmpty else { return }
		if colorsEnabled, let pair = colorPair(for: role) {
			tui_attron_color_pair(pair.identifier)
			s.withCString { cstr in tui_addstr(cstr) }
			tui_attroff_color_pair(pair.identifier)
		} else {
			s.withCString { cstr in tui_addstr(cstr) }
		}
	}
	
	private func renderEditor(buf: EditorBuffer, layout: LayoutMetrics) {
		var scrollRow = buf.scrollRow

		if buf.cursorRow < scrollRow {
			scrollRow = buf.cursorRow
		}
		let bottomVisible = Int(scrollRow) + Int(layout.editorHeight) - 1
		if buf.cursorRow > bottomVisible {
			scrollRow = max(0, buf.cursorRow - Int(layout.editorHeight) + 1)
		}
		
		let maxLine = min(buf.lines.count, Int(scrollRow) + Int(layout.editorHeight))
		let selection = buf.hasSelection ? buf.selection?.normalized : nil
		let gutterWidth = layout.gutterWidth
		let contentWidth = max(1, Int(layout.cols - gutterWidth) - 1)
		var screenRow = layout.editorTop
		for i in Int(scrollRow)..<maxLine {
			let rawLine = buf.lines[i]
			let clipped = TextWidth.clip(rawLine, max: contentWidth)
			move(screenRow, 0)
			clrtoeol()
			if gutterWidth > 0 {
				let gutterDigits = max(1, Int(gutterWidth) - 1)
				let gutterText = String(format: "%\(gutterDigits)d ", i + 1)
				let clippedGutter = TextWidth.clip(gutterText, max: Int(gutterWidth))
				put(screenRow, 0, clippedGutter, role: .gutter)
			}
			move(screenRow, gutterWidth)
			if let selectionRange = selectionColumns(forRow: i, selection: selection) {
				let begin = max(0, selectionRange.lowerBound)
				let end = min(selectionRange.upperBound, clipped.count)
				if begin < end {
					let prefix = substring(clipped, start: 0, end: begin)
					let highlight = substring(clipped, start: begin, end: end)
					let suffix = substring(clipped, start: end, end: clipped.count)
					append(prefix)
					if colorsEnabled, colorPair(for: .selection) != nil {
						append(highlight, role: .selection)
					} else {
						tui_reverse_on()
						append(highlight)
						tui_reverse_off()
					}
					append(suffix)
				} else {
					append(clipped)
				}
			} else {
				append(clipped)
			}
			screenRow += 1
		}
		
		let cursorScrRow = layout.editorTop + Int32(buf.cursorRow - scrollRow)
		let maxCursorCol = max(0, min(buf.cursorCol, contentWidth))
		let cursorColumn = layout.gutterWidth + Int32(maxCursorCol)
		let cursorScrCol = min(max(0, layout.cols - 1), cursorColumn)
		move(cursorScrRow, cursorScrCol)
	}
	
	private func drawDiagnostics(provider: DiagnosticsProvider, top: Int32, height: Int32, width: Int32) {
		mvhline(top - 1, 0, 0, width)
		let diagnostics = provider.currentDiagnostics().prefix(Int(height))
		var r = top
		for diagnostic in diagnostics {
			let severity: String
			switch diagnostic.severity {
				case .error: severity = "E"
				case .warning: severity = "W"
				case .hint: severity = "H"
				case .unknown: severity = "?"
				case .info: severity = "I"
			}
			let line = "\(severity) L\(diagnostic.line+1):\(diagnostic.column+1) \(diagnostic.message)"
			put(r, 1, TextWidth.clip(line, max: Int(width) - 2))
			r += 1
			if r >= top + height {
				break
			}
		}
	}
	
	private func drawHeader(title: String) {
		// Équivalent des anciens mvprintw(...)
		put(1, max(0, ((Int32(tui_cols()) - Int32(title.count)) / 2)), title)
		mvhline(2, 0, 0, (Int32(tui_cols())))
		put(4, 2, "Hello from ncurses!")
		put(6, 2, "• Mouse/keys enabled")
		put(7, 2, "• UTF-8 locale set (if terminal supports it)")
		put(9, 2, "Try typing; press 'q' to quit.")
	}

	private func selectionColumns(forRow row: Int, selection: (start: EditorBuffer.Cursor, end: EditorBuffer.Cursor)?) -> Range<Int>? {
		guard let selection else { return nil }
		if row < selection.start.row || row > selection.end.row { return nil }
		let startCol = row == selection.start.row ? selection.start.column : 0
		let endCol: Int
		if row == selection.end.row {
			endCol = selection.end.column
		} else {
			endCol = Int.max
		}
		if startCol >= endCol { return nil }
		return startCol..<endCol
	}

	private func substring(_ string: String, start: Int, end: Int) -> String {
		if start >= end { return "" }
		let clampedStart = max(0, min(start, string.count))
		let clampedEnd = max(0, min(end, string.count))
		if clampedStart >= clampedEnd { return "" }
		let startIndex = string.index(string.startIndex, offsetBy: clampedStart)
		let endIndex = string.index(string.startIndex, offsetBy: clampedEnd)
		return String(string[startIndex..<endIndex])
	}

	private func append(_ s: String) {
		guard !s.isEmpty else { return }
		s.withCString { cstr in tui_addstr(cstr) }
	}

	private func handleEscapeSequence(maxLength: Int = 8) -> Bool {
		tui_nodelay(true)
		defer { tui_nodelay(false) }
		var codes: [Int32] = []
		while codes.count < maxLength {
			let next = getch()
			if next == ERR { break }
			let value = Int32(next)
			codes.append(value)
			if isTerminatingEscapeCode(value) { break }
		}
		guard !codes.isEmpty else { return false }
		let asciiSequence = asciiString(from: codes)
		let hexSequence = codes.map { String(format: "%X", Int($0)) }.joined(separator: " ")
		let asciiDisplay = asciiSequence ?? "<non-ascii>"
		logger.info("ESC sequence raw=[\(hexSequence)] ascii=\(asciiDisplay)")
		if let asciiSequence, handleMetaWordSequence(asciiSequence, codes: codes) {
			return true
		}
		if handleArrowEscapeSequence(codes) {
			return true
		}
		logger.debug("ESC sequence consumed without action")
		return true
	}

	private func handleMetaWordSequence(_ sequence: String, codes: [Int32]) -> Bool {
		switch sequence {
		case "b":
			logger.debug("ESC meta sequence \(sequence) -> previousWord selecting=false")
			recordKeyInspector(sequence: codes, ascii: sequence, note: "meta previousWord selecting=false")
			mutateBuffer { buffer in
				buffer.moveToPreviousWord()
				return nil
			}
			return true
		case "f":
			logger.debug("ESC meta sequence \(sequence) -> nextWord selecting=false")
			recordKeyInspector(sequence: codes, ascii: sequence, note: "meta nextWord selecting=false")
			mutateBuffer { buffer in
				buffer.moveToNextWord()
				return nil
			}
			return true
		case "B":
			logger.debug("ESC meta sequence \(sequence) -> previousWord selecting=true")
			recordKeyInspector(sequence: codes, ascii: sequence, note: "meta previousWord selecting=true")
			mutateBuffer { buffer in
				buffer.moveToPreviousWord(selecting: true)
				return nil
			}
			return true
		case "F":
			logger.debug("ESC meta sequence \(sequence) -> nextWord selecting=true")
			recordKeyInspector(sequence: codes, ascii: sequence, note: "meta nextWord selecting=true")
			mutateBuffer { buffer in
				buffer.moveToNextWord(selecting: true)
				return nil
			}
			return true
		default:
			logger.debug("ESC meta sequence \(sequence) unhandled")
			recordKeyInspector(sequence: codes, ascii: sequence, note: "meta sequence unhandled")
			return false
		}
	}

	private func handleArrowEscapeSequence(_ codes: [Int32]) -> Bool {
		if let sequence = asciiString(from: codes) {
			guard sequence.hasPrefix("[") else {
				logger.debug("ESC arrow sequence \(sequence) missing prefix")
				return false
			}
			let selecting = escapeSequenceHasShiftModifier(sequence)
			if sequence.hasSuffix("D") {
				logger.debug("ESC arrow sequence \(sequence) -> previousWord selecting=\(selecting)")
				recordKeyInspector(sequence: codes, ascii: sequence, note: selecting ? "word left selecting" : "word left")
				mutateBuffer { buffer in
					buffer.moveToPreviousWord(selecting: selecting)
					return nil
				}
				return true
			}
			if sequence.hasSuffix("C") {
				logger.debug("ESC arrow sequence \(sequence) -> nextWord selecting=\(selecting)")
				recordKeyInspector(sequence: codes, ascii: sequence, note: selecting ? "word right selecting" : "word right")
				mutateBuffer { buffer in
					buffer.moveToNextWord(selecting: selecting)
					return nil
				}
				return true
			}
			logger.debug("ESC arrow sequence \(sequence) unhandled")
			recordKeyInspector(sequence: codes, ascii: sequence, note: "arrow sequence unhandled")
			return false
		}
		if let keyCode = codes.first {
			switch keyCode {
			case KEY_LEFT, KEY_COMMAND, Int32(0x221): // Option+Left
				logger.debug("ESC arrow keyCode \(keyCode) -> previousWord selecting=false")
				recordKeyInspector(key: keyCode, ascii: asciiLabel(for: keyCode), note: "word left")
				mutateBuffer { buffer in
					buffer.moveToPreviousWord()
					return nil
				}
				return true
			case KEY_RIGHT, KEY_OPEN, Int32(0x230): // Option+Right
				logger.debug("ESC arrow keyCode \(keyCode) -> nextWord selecting=false")
				recordKeyInspector(key: keyCode, ascii: asciiLabel(for: keyCode), note: "word right")
				mutateBuffer { buffer in
					buffer.moveToNextWord()
					return nil
				}
				return true
			case KEY_SLEFT, KEY_COPY, Int32(0x222): // Shift+Option+Left
				logger.debug("ESC arrow keyCode \(keyCode) -> previousWord selecting=true")
				recordKeyInspector(key: keyCode, ascii: asciiLabel(for: keyCode), note: "word left selecting")
				mutateBuffer { buffer in
					buffer.moveToPreviousWord(selecting: true)
					return nil
				}
				return true
			case KEY_SRIGHT, KEY_OPTIONS, Int32(0x231): // Shift+Option+Right
				logger.debug("ESC arrow keyCode \(keyCode) -> nextWord selecting=true")
				recordKeyInspector(key: keyCode, ascii: asciiLabel(for: keyCode), note: "word right selecting")
				mutateBuffer { buffer in
					buffer.moveToNextWord(selecting: true)
					return nil
				}
				return true
			case KEY_UP, KEY_REPLACE, Int32(0x236): // Option+Up
				logger.debug("ESC arrow keyCode \(keyCode) -> moveCursor dRow=-1 selecting=false")
				recordKeyInspector(key: keyCode, ascii: asciiLabel(for: keyCode), note: "cursor up")
				mutateBuffer { buffer in
					buffer.moveCursor(dRow: -1, dCol: 0)
					return nil
				}
				return true
			case KEY_DOWN, KEY_CTAB, Int32(0x20D): // Option+Down
				logger.debug("ESC arrow keyCode \(keyCode) -> moveCursor dRow=1 selecting=false")
				recordKeyInspector(key: keyCode, ascii: asciiLabel(for: keyCode), note: "cursor down")
				mutateBuffer { buffer in
					buffer.moveCursor(dRow: 1, dCol: 0)
					return nil
				}
				return true
			case KEY_RESTART:
				logger.debug("ESC arrow keyCode KEY_RESTART -> moveCursor dRow=-1 selecting=true")
				mutateBuffer { buffer in
					buffer.moveCursor(dRow: -1, dCol: 0, selecting: true)
					return nil
				}
				return true
			case KEY_CATAB:
				logger.debug("ESC arrow keyCode KEY_CATAB -> moveCursor dRow=1 selecting=true")
				mutateBuffer { buffer in
					buffer.moveCursor(dRow: 1, dCol: 0, selecting: true)
					return nil
				}
				return true
			default:
				logger.debug("ESC arrow keyCode \(keyCode) unhandled")
				recordKeyInspector(key: keyCode, ascii: asciiLabel(for: keyCode), note: "arrow key unhandled")
			}
		}
		return false
	}

	private func isTerminatingEscapeCode(_ code: Int32) -> Bool {
		if code < 0 || code > 255 { return true }
		if let scalar = UnicodeScalar(UInt32(code)) {
			if CharacterSet.letters.contains(scalar) { return true }
			if scalar == "~" { return true }
		}
		return false
	}

	private func asciiString(from codes: [Int32]) -> String? {
		var scalars: [UnicodeScalar] = []
		scalars.reserveCapacity(codes.count)
		for code in codes {
			guard code >= 0, code <= 255, let scalar = UnicodeScalar(UInt32(code)) else { return nil }
			scalars.append(scalar)
		}
		return String(String.UnicodeScalarView(scalars))
	}

	private func escapeSequenceHasShiftModifier(_ sequence: String) -> Bool {
		guard let semicolonIndex = sequence.lastIndex(of: ";") else { return false }
		let modifierStart = sequence.index(after: semicolonIndex)
		let modifierEnd = sequence.index(before: sequence.endIndex)
		guard modifierStart < modifierEnd else { return false }
		let modifierSlice = sequence[modifierStart..<modifierEnd]
		guard let modifier = Int(modifierSlice) else { return false }
		return modifier % 2 == 0
	}
}

private extension Logger.Level {
	init?(envValue: String) {
		switch envValue.lowercased() {
		case "trace":
			self = .trace
		case "debug":
			self = .debug
		case "info":
			self = .info
		case "notice":
			self = .notice
		case "warning", "warn":
			self = .warning
		case "error", "err":
			self = .error
		case "critical", "crit":
			self = .critical
		default:
			return nil
		}
	}
}

#if DEBUG
extension TextUserInterfaceApp {
	func _debugSetBuffer(_ buffer: EditorBuffer?) {
		self.buffer = buffer
	}

	func _debugBuffer() -> EditorBuffer? {
		buffer
	}

	func _debugEnableInspector(_ enabled: Bool = true) {
		keyInspector.isEnabled = enabled
		if !enabled {
			keyInspector.entries.removeAll()
		}
	}

	func _debugInspectorNotes() -> [String] {
		keyInspector.entries.map { "\($0.rawLabel)|\($0.note)" }
	}

	func _debugHandleEscapeSequence(codes: [Int32]) -> Bool {
		if let asciiSequence = asciiString(from: codes), handleMetaWordSequence(asciiSequence, codes: codes) {
			return true
		}
		return handleArrowEscapeSequence(codes)
	}

	func _debugHandleMetaWordSequence(_ sequence: String) -> Bool {
		handleMetaWordSequence(sequence, codes: [])
	}

	func _debugHandleArrowEscapeSequence(_ codes: [Int32]) -> Bool {
		handleArrowEscapeSequence(codes)
	}

	func _debugEscapeSequenceHasShiftModifier(_ sequence: String) -> Bool {
		escapeSequenceHasShiftModifier(sequence)
	}

	func _debugSetDocumentURL(_ url: URL?) {
		documentURL = url
	}

	func _debugDocumentURL() -> URL? {
		documentURL
	}

	func _debugIsDirty() -> Bool {
		isDirty
	}

	func _debugMarkDirty(_ dirty: Bool) {
		isDirty = dirty
	}

	@discardableResult
	func _debugSaveDocument() -> Bool {
		saveDocument()
	}

	@discardableResult
	func _debugHandleSearchKey(_ key: Int32) -> Bool {
		let outcome = handleSearchInput(key: key, ascii: asciiLabel(for: key))
		if case .handled = outcome { return true }
		return false
	}

	func _debugIsSearchMode() -> Bool {
		if case .search = inputMode { return true }
		return false
	}

	func _debugLastSearchQuery() -> String? {
		lastSearch?.query
	}

	func _debugNavigationDepths() -> (back: Int, forward: Int) {
		(navigationBack.count, navigationForward.count)
	}

	@discardableResult
	func _debugNavigateBack() -> Bool {
		navigateBack()
	}

	@discardableResult
	func _debugNavigateForward() -> Bool {
		navigateForward()
	}

	@discardableResult
	func _debugHandleCommandKey(_ key: Int32) -> Bool {
		let outcome = handleCommandPaletteInput(key: key, ascii: asciiLabel(for: key))
		if case .handled = outcome { return true }
		return false
	}

	func _debugIsCommandPaletteMode() -> Bool {
		if case .commandPalette = inputMode { return true }
		return false
	}

	func _debugCommandPaletteQuery() -> String? {
		if case .commandPalette(let state) = inputMode {
			return state.query
		}
		return nil
	}

	func _debugLayout(rows: Int32, cols: Int32, lineCount: Int, inspector: Bool = false, diagnosticsHeight: Int32 = 0) -> LayoutMetrics {
		let safeCount = max(1, lineCount)
		let lines = Array(repeating: "", count: safeCount)
		let buffer = EditorBuffer(lines: lines)
		return makeLayout(
			rows: rows,
			cols: cols,
			inspectorHeight: inspector ? inspectorPanelHeight : 0,
			diagnosticsHeight: diagnosticsHeight,
			buffer: buffer
		)
	}
}
#endif
