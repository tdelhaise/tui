
import Foundation

@MainActor
public enum Log {
	public static var isVerbose = true
	
	public static func info(_ msg: @autoclosure () -> String) {
		if isVerbose { fputs("[INFO] \(msg())\n", stderr) }
	}
	public static func warn(_ msg: @autoclosure () -> String) {
		fputs("[WARN] \(msg())\n", stderr)
	}
	public static func error(_ msg: @autoclosure () -> String) {
		fputs("[ERROR] \(msg())\n", stderr)
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
