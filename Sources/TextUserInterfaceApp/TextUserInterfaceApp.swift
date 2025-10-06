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

	private let inspectorCapacity = 6
	private let inspectorPanelHeight: Int32 = 8
	private var keyInspector: KeyInspectorState

	// éventuellement:
	private weak var diagsProvider: DiagnosticsProvider?
	private var statusMessage: String = ""

	public init(enableKeyInspector: Bool = false) {
		var log = Logger(label: "TextUserInterfaceApp")
		log.logLevel = Self.resolveLogLevel()
		self.logger = log
		self.keyInspector = KeyInspectorState(isEnabled: enableKeyInspector, entries: [])
	}
	
	private static func resolveLogLevel() -> Logger.Level {
		guard let raw = ProcessInfo.processInfo.environment["TUI_LOG_LEVEL"],
				let level = Logger.Level(envValue: raw) else {
			return .info
		}
		return level
	}
	
	public func run(buffer: EditorBuffer?, diagsProvider: DiagnosticsProvider?, enableKeyInspector: Bool = false) {
		self.buffer = buffer
		self.diagsProvider = diagsProvider
		keyInspector.isEnabled = enableKeyInspector
		keyInspector.entries.removeAll(keepingCapacity: true)
		
		initscr()
		defer { endwin() }
		
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
		
		while running {
			erase()
			
			let cols: Int32 = Int32(tui_cols())   // wrappers -> pas d’accès direct à COLS/LINES
			let rows: Int32 = Int32(tui_lines())
			let reservedRows: Int32 = 2
			let inspectorHeight: Int32 = keyInspector.isEnabled ? inspectorPanelHeight : 0
			var editorRows = rows - reservedRows - inspectorHeight
			editorRows = max(5, editorRows)
			if diagsProvider != nil && diagHeight > 0 {
				editorRows = max(5, editorRows - diagHeight)
			}
			
			put(0, 0, "tui — q/ESC:quit  arrows:move  Shift+arrows:select  Home/End  PgUp/PgDn  v:select  y:copy  x:cut  p:paste  d:diag")
			mvhline(1, 0, 0, cols)
			
			if let buf = buffer {
				renderEditor(buf: buf, top: 2, height: editorRows, width: cols)
			} else {
				put(3, 2, "No file open. Use --file <path> to open a file.")
			}
			
			if let provider = diagsProvider, diagHeight > 0 {
				let top = rows - diagHeight
				drawDiagnostics(provider: provider, top: top, height: diagHeight, width: cols)
			}
			
			refresh()
			let ch = getch()
			let key = Int32(ch)
			let hexString = String(format:"%08X", key)
			let asciiSummary = asciiLabel(for: key)
			var inspectorNote: String? = nil
			
			switch key {
			case 27, 113:
				if key == 27 {
					if handleEscapeSequence() {
						continue
					}
					logger.info("key: \(hexString) aka \(key)")
					inspectorNote = "escape"
				} else {
					logger.info("key: \(hexString) aka \(key)")
					inspectorNote = "quit"
				}
				running = false
				
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
					buffer.pageScroll(page: +1, viewRows: Int(editorRows))
					return nil
				}
			case KEY_PPAGE:
				logger.info("key: \(hexString) aka \(key) aka KEY_PPAGE")
				inspectorNote = "page up"
				mutateBuffer { buffer in
					buffer.pageScroll(page: -1, viewRows: Int(editorRows))
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
			case KEY_BREAK:
				logger.info("key: \(hexString) aka \(key) aka KEY_BREAK")
				break
			case KEY_SRESET:
				logger.info("key: \(hexString) aka \(key) aka KEY_SRESET")
				break
			case KEY_RESET:
				logger.info("key: \(hexString) aka \(key) aka KEY_RESET")
				break
			case KEY_DOWN:
				logger.info("key: \(hexString) aka \(key) aka KEY_DOWN")
				break
			case KEY_UP:
				logger.info("key: \(hexString) aka \(key) aka KEY_UP")
				break
			case KEY_LEFT:
				logger.info("key: \(hexString) aka \(key) aka KEY_LEFT")
				break
			case KEY_RIGHT:
				logger.info("key: \(hexString) aka \(key) aka KEY_RIGHT")
				break
			case KEY_HOME:
				logger.info("key: \(hexString) aka \(key) aka KEY_HOME")
				break
			case KEY_BACKSPACE:
				logger.info("key: \(hexString) aka \(key) aka KEY_BACKSPACE")
				break
			case KEY_F0:
				logger.info("key: \(hexString) aka \(key) aka KEY_F0")
				break
			case KEY_F0+1:
				logger.info("key: \(hexString) aka \(key) aka KEY_F1")
				break
			case KEY_F0+2:
				logger.info("key: \(hexString) aka \(key) aka KEY_F2")
				break
			case KEY_F0+3:
				logger.info("key: \(hexString) aka \(key) aka KEY_F3")
				break
			case KEY_F0+4:
				logger.info("key: \(hexString) aka \(key) aka KEY_F4")
				break
			case KEY_F0+5:
				logger.info("key: \(hexString) aka \(key) aka KEY_F5")
				break
			case KEY_F0+6:
				logger.info("key: \(hexString) aka \(key) aka KEY_F7")
				break
			case KEY_F0+7:
				logger.info("key: \(hexString) aka \(key) aka KEY_F8")
				break
			case KEY_F0+8:
				logger.info("key: \(hexString) aka \(key) aka KEY_F9")
				break
			case KEY_F0+9:
				logger.info("key: \(hexString) aka \(key) aka KEY_F10")
				break
			case KEY_F0+10:
				logger.info("key: \(hexString) aka \(key) aka KEY_F11")
				break
			case KEY_DL:
				logger.info("key: \(hexString) aka \(key) aka KEY_DL")
				break
			case KEY_IL:
				logger.info("key: \(hexString) aka \(key) aka KEY_IL")
				break
			case KEY_DC:
				logger.info("key: \(hexString) aka \(key) aka KEY_DC")
				break
			case KEY_IC:
				logger.info("key: \(hexString) aka \(key) aka KEY_IC")
				break
			case KEY_EIC:
				logger.info("key: \(hexString) aka \(key) aka KEY_EIC")
				break
			case KEY_CLEAR:
				logger.info("key: \(hexString) aka \(key) aka KEY_CLEAR")
				break
			case KEY_EOS:
				logger.info("key: \(hexString) aka \(key) aka KEY_EOS")
				break
			case KEY_EOL:
				logger.info("key: \(hexString) aka \(key) aka KEY_EOL")
				break
			case KEY_SF:
				logger.info("key: \(hexString) aka \(key) aka KEY_SF")
				break
			case KEY_SR:
				logger.info("key: \(hexString) aka \(key) aka KEY_SR")
				break
			case KEY_NPAGE:
				logger.info("key: \(hexString) aka \(key) aka KEY_NPAGE")
				inspectorNote = "page down"
				break
			case KEY_PPAGE:
				logger.info("key: \(hexString) aka \(key) aka KEY_PPAGE")
				inspectorNote = "page up"
				break
			case KEY_STAB:
				logger.info("key: \(hexString) aka \(key) aka KEY_STAB")
				break
			case KEY_CTAB:
				logger.info("key: \(hexString) aka \(key) aka KEY_CTAB")
				break
			case KEY_CATAB, Int32(0x20E): // Shift+Option+Down
				logger.info("key: \(hexString) aka \(key) aka KEY_CATAB")
				break
			case KEY_ENTER:
				logger.info("key: \(hexString) aka \(key) aka KEY_ENTER")
				break
			case KEY_PRINT:
				logger.info("key: \(hexString) aka \(key) aka KEY_PRINT")
				break
			case KEY_LL:
				logger.info("key: \(hexString) aka \(key) aka KEY_LL")
				break
			case KEY_A1:
				logger.info("key: \(hexString) aka \(key) aka KEY_A1")
				break
			case KEY_A3:
				logger.info("key: \(hexString) aka \(key) aka KEY_A3")
				break
			case KEY_B2:
				logger.info("key: \(hexString) aka \(key) aka KEY_B2")
				break
			case KEY_C1:
				logger.info("key: \(hexString) aka \(key) aka KEY_C1")
				break
			case KEY_C3:
				logger.info("key: \(hexString) aka \(key) aka KEY_C3")
				break
			case KEY_BTAB:
				logger.info("key: \(hexString) aka \(key) aka KEY_BTAB")
				break
			case KEY_BEG:
				logger.info("key: \(hexString) aka \(key) aka KEY_BEG")
				break
			case KEY_CANCEL:
				logger.info("key: \(hexString) aka \(key) aka KEY_CANCEL")
				break
			case KEY_CLOSE:
				logger.info("key: \(hexString) aka \(key) aka KEY_CLOSE")
				break
			case KEY_COMMAND:
				logger.info("key: \(hexString) aka \(key) aka KEY_COMMAND")
				break
			case KEY_COPY:
				logger.info("key: \(hexString) aka \(key) aka KEY_COPY")
				break
			case KEY_CREATE:
				logger.info("key: \(hexString) aka \(key) aka KEY_CREATE")
				break
			case KEY_END:
				logger.info("key: \(hexString) aka \(key) aka KEY_END")
				break
			case KEY_EXIT:
				logger.info("key: \(hexString) aka \(key) aka KEY_EXIT")
				break
			case KEY_FIND:
				logger.info("key: \(hexString) aka \(key) aka KEY_FIND")
				break
			case KEY_HELP:
				logger.info("key: \(hexString) aka \(key) aka KEY_HELP")
				break
			case KEY_MARK:
				logger.info("key: \(hexString) aka \(key) aka KEY_MARK")
				break
			case KEY_MESSAGE:
				logger.info("key: \(hexString) aka \(key) aka KEY_MESSAGE")
				break
			case KEY_MOVE:
				logger.info("key: \(hexString) aka \(key) aka KEY_MOVE")
				break
			case KEY_NEXT:
				logger.info("key: \(hexString) aka \(key) aka KEY_NEXT")
				break
			case KEY_OPEN:
				logger.info("key: \(hexString) aka \(key) aka KEY_OPEN")
				break
			case KEY_OPTIONS:
				logger.info("key: \(hexString) aka \(key) aka KEY_OPTIONS")
				break
			case KEY_PREVIOUS:
				logger.info("key: \(hexString) aka \(key) aka KEY_PREVIOUS")
				break
			case KEY_REDO:
				logger.info("key: \(hexString) aka \(key) aka KEY_REDO")
				break
			case KEY_REFERENCE:
				logger.info("key: \(hexString) aka \(key) aka KEY_REFERENCE")
				break
			case KEY_REFRESH:
				logger.info("key: \(hexString) aka \(key) aka KEY_REFRESH")
				break
			case KEY_REPLACE:
				logger.info("key: \(hexString) aka \(key) aka KEY_REPLACE")
				break
			case KEY_RESTART, Int32(0x237): // Shift+Option+Up
				logger.info("key: \(hexString) aka \(key) aka KEY_RESTART")
				break
			case KEY_RESUME:
				logger.info("key: \(hexString) aka \(key) aka KEY_RESUME")
				break
			case KEY_SAVE:
				logger.info("key: \(hexString) aka \(key) aka KEY_SAVE")
				break
			case KEY_SBEG:
				logger.info("key: \(hexString) aka \(key) aka KEY_SBEG")
				break
			case KEY_SCANCEL:
				logger.info("key: \(hexString) aka \(key) aka KEY_SCANCEL")
				break
			case KEY_SCOMMAND:
				logger.info("key: \(hexString) aka \(key) aka KEY_SCOMMAND")
				break
			case KEY_SCOPY:
				logger.info("key: \(hexString) aka \(key) aka KEY_SCOPY")
				break
			case KEY_SCREATE:
				logger.info("key: \(hexString) aka \(key) aka KEY_SCREATE")
				break
			case KEY_SDC:
				logger.info("key: \(hexString) aka \(key) aka KEY_SDC")
				break
			case KEY_SDL:
				logger.info("key: \(hexString) aka \(key) aka KEY_SDL")
				break
			case KEY_SELECT:
				logger.info("key: \(hexString) aka \(key) aka KEY_SELECT")
				break
			case KEY_SEND:
				logger.info("key: \(hexString) aka \(key) aka KEY_SEND")
				inspectorNote = "select line end"
				break
			case KEY_SEOL:
				logger.info("key: \(hexString) aka \(key) aka KEY_SEOL")
				break
			case KEY_SEXIT:
				logger.info("key: \(hexString) aka \(key) aka KEY_SEXIT")
				break
			case KEY_SFIND:
				logger.info("key: \(hexString) aka \(key) aka KEY_SFIND")
				break
			case KEY_SHELP:
				logger.info("key: \(hexString) aka \(key) aka KEY_SHELP")
				break
			case KEY_SHOME:
				logger.info("key: \(hexString) aka \(key) aka KEY_SHOME")
				inspectorNote = "select line start"
				break
			case KEY_SIC:
				logger.info("key: \(hexString) aka \(key) aka KEY_SIC")
				break
			case KEY_SLEFT:
				logger.info("key: \(hexString) aka \(key) aka KEY_SLEFT")
				break
			case KEY_SMESSAGE:
				logger.info("key: \(hexString) aka \(key) aka KEY_SMESSAGE")
				break
			case KEY_SMOVE:
				logger.info("key: \(hexString) aka \(key) aka KEY_SMOVE")
				break
			case KEY_SNEXT:
				logger.info("key: \(hexString) aka \(key) aka KEY_SNEXT")
				break
			case KEY_SOPTIONS:
				logger.info("key: \(hexString) aka \(key) aka KEY_SOPTIONS")
				break
			case KEY_SPREVIOUS:
				logger.info("key: \(hexString) aka \(key) aka KEY_SPREVIOUS")
				break
			case KEY_SPRINT:
				logger.info("key: \(hexString) aka \(key) aka KEY_SPRINT")
				break
			case KEY_SREDO:
				logger.info("key: \(hexString) aka \(key) aka KEY_SREDO")
				break
			case KEY_SREPLACE:
				logger.info("key: \(hexString) aka \(key) aka KEY_SREPLACE")
				break
			case KEY_SRIGHT:
				logger.info("key: \(hexString) aka \(key) aka KEY_SRIGHT")
				inspectorNote = "select right"
				break
			case KEY_SRSUME:
				logger.info("key: \(hexString) aka \(key) aka KEY_SRSUME")
				break
			case KEY_SSAVE:
				logger.info("key: \(hexString) aka \(key) aka KEY_SSAVE")
				break
			case KEY_SSUSPEND:
				logger.info("key: \(hexString) aka \(key) aka KEY_SSUSPEND")
				break
			case KEY_SUNDO:
				logger.info("key: \(hexString) aka \(key) aka KEY_SUNDO")
				break
			case KEY_SUSPEND:
				logger.info("key: \(hexString) aka \(key) aka KEY_SUSPEND")
				break
			case KEY_UNDO:
				logger.info("key: \(hexString) aka \(key) aka KEY_UNDO")
				break
			case KEY_MOUSE:
				logger.info("key: \(hexString) aka \(key) aka KEY_MOUSE")
				break
			case KEY_RESIZE:
				logger.info("key: \(hexString) aka \(key) aka KEY_RESIZE")
				break
#if os(Windows)
			case KEY_EVENT:
				logger.info("key: \(hexString) aka \(key) aka KEY_EVENT")
				break
#endif
			default:
				logger.info("key: \(hexString) aka \(key)")
				break
			}

			if let note = inspectorNote {
				recordKeyInspector(key: key, ascii: asciiSummary, note: note)
			}

			let keyInfo = "key: \(ch)"
			putCleared(rows - 2, 2, keyInfo)
			var footer = "q/ESC to quit"
			if let buf = buffer {
				footer = "pos \(buf.cursorRow + 1):\(buf.cursorCol + 1)"
				if let selectionLength = buf.selectionLength() {
					footer += "  sel=\(selectionLength)"
				}
				footer += "  q/ESC to quit"
			}
			if !statusMessage.isEmpty {
				footer += "  " + statusMessage
			}
			putCleared(rows - 1, 2, footer)
			statusMessage = ""
		}
	}
	
	private func mutateBuffer(_ body: (inout EditorBuffer) -> String?) {
		guard var buf = buffer else { return }
		let message = body(&buf)
		buffer = buf
		if let message {
			statusMessage = message
		}
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
		putCleared(top + 1, 1, TextWidth.clip(header, max: Int(width) - 2))
		let availableRows = max(0, Int(height) - 2)
		guard availableRows > 0 else { return }
		let recent = keyInspector.entries.suffix(availableRows)
		var row = top + 2
		for entry in recent.reversed() {
			let line = "\(entry.rawLabel)  \(entry.asciiLabel)  \(entry.note)"
			putCleared(row, 1, TextWidth.clip(line, max: Int(width) - 2))
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

	private func putCleared(_ y: Int32, _ x: Int32, _ s: String) {
		move(y, x)
		clrtoeol()
		put(y, x, s)
	}

	// Helpers non-variadiques
	private func put(_ y: Int32, _ x: Int32, _ s: String) {
		move(y, x)
		s.withCString { cstr in tui_addstr(cstr) }  // wrapper addstr + ignore le résultat
	}
	
	private func renderEditor(buf: EditorBuffer, top: Int32, height: Int32, width: Int32) {
		var scrollRow = buf.scrollRow

		if buf.cursorRow < scrollRow {
			scrollRow = buf.cursorRow
		}
		let bottomVisible = Int(scrollRow) + Int(height) - 1
		if buf.cursorRow > bottomVisible {
			scrollRow = max(0, buf.cursorRow - Int(height) + 1)
		}
		
		let maxLine = min(buf.lines.count, Int(scrollRow) + Int(height))
		let selection = buf.hasSelection ? buf.selection?.normalized : nil
		var screenRow = top
		for i in Int(scrollRow)..<maxLine {
			let rawLine = buf.lines[i]
			let clipped = TextWidth.clip(rawLine, max: Int(width) - 1)
			move(screenRow, 0)
			clrtoeol()
			if let selectionRange = selectionColumns(forRow: i, selection: selection) {
				let begin = max(0, selectionRange.lowerBound)
				let end = min(selectionRange.upperBound, clipped.count)
				if begin < end {
					let prefix = substring(clipped, start: 0, end: begin)
					let highlight = substring(clipped, start: begin, end: end)
					let suffix = substring(clipped, start: end, end: clipped.count)
					append(prefix)
					tui_reverse_on()
					append(highlight)
					tui_reverse_off()
					append(suffix)
				} else {
					append(clipped)
				}
			} else {
				append(clipped)
			}
			screenRow += 1
		}
		
		let cursorScrRow = top + Int32(buf.cursorRow - scrollRow)
		let cursorScrCol = Int32(min(buf.cursorCol, Int(width) - 1))
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
}
#endif
