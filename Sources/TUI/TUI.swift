import Foundation
import CNcurses
import Utilities
import Editors
import Workspace

public protocol DiagnosticsProvider: AnyObject {
	func currentDiagnostics() -> [Diagnostic]
}

@MainActor
public final class TUIApp {
	public init() {}
	
	public func run(buffer: EditorBuffer?, diagsProvider: DiagnosticsProvider?) {
		initscr()
		defer { endwin() }
		raw()
		tui_keypad_enable() // wrapper -> pas d’accès direct à stdscr
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
			
			put(0, 0, "tui — q/ESC:quit  arrows:move  PgUp/PgDn:scroll  d:toggle-diagnostics")
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
			switch Int32(ch) {
			case 27, 113: running = false                // ESC/q
			case KEY_UP:   buffer?.moveCursor(dRow: -1, dCol: 0)
			case KEY_DOWN: buffer?.moveCursor(dRow:  1, dCol: 0)
			case KEY_LEFT: buffer?.moveCursor(dRow:  0, dCol: -1)
			case KEY_RIGHT:buffer?.moveCursor(dRow:  0, dCol:  1)
			case KEY_NPAGE: if let b = buffer { b.pageScroll(page: +1, viewRows: Int(editorRows)) }
			case KEY_PPAGE: if let b = buffer { b.pageScroll(page: -1, viewRows: Int(editorRows)) }
			case 100: diagHeight = (diagHeight == 0) ? 8 : 0   // 'd'
			default: break
			}
			
			put(rows - 2, 2, "key: \(ch)     ")
			put(rows - 1, 2, "Press 'q' or ESC to quit.")
		}
	}
	
	// Helpers non-variadiques
	private func put(_ y: Int32, _ x: Int32, _ s: String) {
		move(y, x)
		s.withCString { cstr in tui_addstr(cstr) }  // wrapper addstr + ignore le résultat
	}
	
	private func renderEditor(buf: EditorBuffer, top: Int32, height: Int32, width: Int32) {
		if buf.cursorRow < buf.scrollRow { buf.scrollRow = buf.cursorRow }
		let bottomVisible = Int(buf.scrollRow) + Int(height) - 1
		if buf.cursorRow > bottomVisible { buf.scrollRow = max(0, buf.cursorRow - Int(height) + 1) }
		
		let maxLine = min(buf.lines.count, Int(buf.scrollRow) + Int(height))
		var screenRow = top
		for i in Int(buf.scrollRow)..<maxLine {
			let line = TextWidth.clip(buf.lines[i], max: Int(width) - 1)
			put(screenRow, 0, line)
			screenRow += 1
		}
		
		let cursorScrRow = top + Int32(buf.cursorRow - buf.scrollRow)
		let cursorScrCol = Int32(min(buf.cursorCol, Int(width) - 1))
		move(cursorScrRow, cursorScrCol)
	}
	
	private func drawDiagnostics(provider: DiagnosticsProvider, top: Int32, height: Int32, width: Int32) {
		mvhline(top - 1, 0, 0, width)
		let diags = provider.currentDiagnostics().prefix(Int(height))
		var r = top
		for d in diags {
			let sev: String
			switch d.severity {
			case .error: sev = "E"
			case .warning: sev = "W"
			case .information: sev = "I"
			case .hint: sev = "H"
			case .unknown: sev = "?"
			}
			let line = "\(sev) L\(d.line+1):\(d.character+1) \(d.message)"
			put(r, 1, TextWidth.clip(line, max: Int(width) - 2))
			r += 1
			if r >= top + height { break }
		}
	}
	
	private func drawHeader(title: String) {
		// Équivalent des anciens mvprintw(...)
		put(1, max(0, (COLS - Int32(title.count)) / 2), title)
		mvhline(2, 0, 0, COLS)
		put(4, 2, "Hello from ncurses!")
		put(6, 2, "• Mouse/keys enabled")
		put(7, 2, "• UTF-8 locale set (if terminal supports it)")
		put(9, 2, "Try typing; press 'q' to quit.")
	}
}
