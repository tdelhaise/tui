import Foundation
import CNcursesShims
import Utilities
import Workspace
import Editors


public protocol DiagnosticsProvider: AnyObject {
	func currentDiagnostics() -> [Diagnostic]
}

@MainActor
public final class TextUserInterfaceApp {
	
	private var buffer: EditorBuffer?      // ⬅️ conserver l’état
	// éventuellement:
	private weak var diagsProvider: DiagnosticsProvider?
	private var statusMessage: String = ""

	public init() {}
	
	public func run(buffer: EditorBuffer?, diagsProvider: DiagnosticsProvider?) {
		self.buffer = buffer
		self.diagsProvider = diagsProvider
		
		initscr()
		defer { endwin() }
		raw()
		tui_keypad_stdscr(true) // wrapper C : on active keypad(stdscr, TRUE)
		noecho()
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
			var editorRows = rows - 2
			if diagsProvider != nil && diagHeight > 0 {
				editorRows = max(5, rows - diagHeight - 2)
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

			switch key {
			case 27, 113:
				running = false
			case KEY_UP:
				mutateBuffer { buffer in
					buffer.moveCursor(dRow: -1, dCol: 0)
					return nil
				}
			case KEY_DOWN:
				mutateBuffer { buffer in
					buffer.moveCursor(dRow: 1, dCol: 0)
					return nil
				}
			case KEY_LEFT:
				mutateBuffer { buffer in
					buffer.moveCursor(dRow: 0, dCol: -1)
					return nil
				}
			case KEY_RIGHT:
				mutateBuffer { buffer in
					buffer.moveCursor(dRow: 0, dCol: 1)
					return nil
				}
			case KEY_SLEFT:
				mutateBuffer { buffer in
					buffer.moveCursor(dRow: 0, dCol: -1, selecting: true)
					return nil
				}
			case KEY_SRIGHT:
				mutateBuffer { buffer in
					buffer.moveCursor(dRow: 0, dCol: 1, selecting: true)
					return nil
				}
			case KEY_HOME:
				mutateBuffer { buffer in
					buffer.moveToLineStart()
					return nil
				}
			case KEY_END:
				mutateBuffer { buffer in
					buffer.moveToLineEnd()
					return nil
				}
			case KEY_SHOME:
				mutateBuffer { buffer in
					buffer.moveToLineStart(selecting: true)
					return nil
				}
			case KEY_SEND:
				mutateBuffer { buffer in
					buffer.moveToLineEnd(selecting: true)
					return nil
				}
			case KEY_NPAGE:
				mutateBuffer { buffer in
					buffer.pageScroll(page: +1, viewRows: Int(editorRows))
					return nil
				}
			case KEY_PPAGE:
				mutateBuffer { buffer in
					buffer.pageScroll(page: -1, viewRows: Int(editorRows))
					return nil
				}
			case 118, 86:
				mutateBuffer { buffer in
					if buffer.hasSelection {
						buffer.clearSelection()
						return "Selection cleared"
					} else {
						buffer.beginSelection()
						return "Selection anchor set"
					}
				}
			case 121, 89:
				mutateBuffer { buffer in
					guard let copied = buffer.copySelection(), !copied.isEmpty else { return "No selection to copy" }
					let preview = summarize(copied)
					notify(title: "Selection Copied", message: preview, kind: .info, metadata: ["length": String(copied.count)])
					return "Copied \\(copied.count) chars"
				}
			case 120, 88:
				mutateBuffer { buffer in
					guard let copied = buffer.copySelection(), !copied.isEmpty else { return "No selection to cut" }
					_ = buffer.deleteSelection()
					let preview = summarize(copied)
					notify(title: "Selection Cut", message: preview, kind: .warning, metadata: ["length": String(copied.count)])
					return "Cut \\(copied.count) chars"
				}
			case 112, 80:
				mutateBuffer { buffer in
					guard !buffer.clipboard.isEmpty else { return "Clipboard empty" }
					buffer.pasteClipboard()
					notify(title: "Clipboard Pasted", message: summarize(buffer.clipboard), kind: .success, metadata: ["length": String(buffer.clipboard.count)])
					return "Pasted \\(buffer.clipboard.count) chars"
				}
			case 100:
				diagHeight = (diagHeight == 0) ? 8 : 0
			default:
				break
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
		var screenRow = top
		for i in Int(scrollRow)..<maxLine {
			let line = TextWidth.clip(buf.lines[i], max: Int(width) - 1)
			put(screenRow, 0, line)
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
}
