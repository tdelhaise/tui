
import Foundation
#if canImport(OSLog)
import OSLog
#endif
#if os(Linux)
import Glibc
#endif

@MainActor
public enum Log {
	public static var isVerbose = true

	private enum Level {
		case info
		case warn
		case error
	}

#if canImport(OSLog)
	private static let osLogger = Logger(subsystem: "io.tui", category: "app")
#endif

#if os(Linux)
	private static var syslogIsOpen = false

	@inline(__always)
	private static func withSyslog(_ body: () -> Void) {
		if !syslogIsOpen {
			openlog("tui", LOG_PID | LOG_CONS, LOG_USER)
			syslogIsOpen = true
		}
		body()
	}
#endif

	public static func info(_ msg: @autoclosure () -> String) {
		guard isVerbose else { return }
		emit(.info, message: msg())
	}
	public static func warn(_ msg: @autoclosure () -> String) {
		emit(.warn, message: msg())
	}
	public static func error(_ msg: @autoclosure () -> String) {
		emit(.error, message: msg())
	}

	private static func emit(_ level: Level, message: String) {
#if canImport(OSLog)
		switch level {
		case .info:
			osLogger.info("\(message, privacy: .public)")
		case .warn:
			osLogger.warning("\(message, privacy: .public)")
		case .error:
			osLogger.error("\(message, privacy: .public)")
		}
#endif

#if os(Linux)
		withSyslog {
			let priority: Int32
			switch level {
			case .info: priority = LOG_INFO
			case .warn: priority = LOG_WARNING
			case .error: priority = LOG_ERR
			}
			message.withCString { cstr in
				syslog(priority, "%s", cstr)
			}
		}
#endif

		let prefix: String
		switch level {
		case .info: prefix = "[INFO]"
		case .warn: prefix = "[WARN]"
		case .error: prefix = "[ERROR]"
		}
		// Mirror to stderr so logs remain visible when platform facilities are unavailable or restricted.
		// fputs("\(prefix) \(message)\n", stderr)
	}
}

public enum Env {
	public static func path() -> [String] {
		(ProcessInfo.processInfo.environment["PATH"] ?? "")
			.split(separator: ":").map(String.init)
	}
}

public extension FileManager {
	func enumerateFiles(at root: URL, includingHidden: Bool = false) -> [URL] {
		let opts: FileManager.DirectoryEnumerationOptions = includingHidden ? [] : [.skipsHiddenFiles]
		var results: [URL] = []
		if let enumerator = self.enumerator(at: root, includingPropertiesForKeys: nil, options: opts) {
			for case let url as URL in enumerator {
				results.append(url)
			}
		}
		return results
	}
}

public enum TextWidth {
	// naïf (ASCII). À remplacer plus tard par une gestion grapheme-aware.
	public static func clip(_ s: String, max cols: Int) -> String {
		if cols <= 0 { return "" }
		if s.count <= cols { return s }
		let idx = s.index(s.startIndex, offsetBy: cols)
		return String(s[..<idx])
	}
}
