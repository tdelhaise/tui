import ArgumentParser
import Foundation
import LSPClient
import Utilities
import TextUserInterfaceApp
import Editors
import Puppy
import Logging

@MainActor
@main
struct TUICommand: AsyncParsableCommand {
	
	@Argument
	var fileToOpen: String? = nil
	
	@Option(name: .shortAndLong, help: "Path to clangd (for C/C++).")
	var clangd: String = "/usr/bin/clangd"
	
	@Option(name: .shortAndLong, help: "Path to sourcekit-lsp (for Swift).")
	var sourcekit: String = "/usr/bin/sourcekit-lsp"

	@Flag(name: .long, help: "Show the live key inspector overlay.")
	var inspectKeys: Bool = false
	
	public mutating func run() async throws {
		
		let subsystem = "org.tui.tui"
		let commandLoggerLabel = "\(subsystem).command"
		let console = ConsoleLogger(commandLoggerLabel)
		var puppy = Puppy(loggers: [console])
#if canImport(Darwin)
		let oslog = OSLogger(subsystem, category: "input")
		puppy.add(oslog)
#elseif os(Linux)
		let syslog = SystemLogger(commandLoggerLabel)
		puppy.add(syslog)
#elseif os(Windows)
#else
#endif // canImport(Darwin)

		LoggingSystem.bootstrap { [puppy] in
			var handler = PuppyLogHandler(label: $0, puppy: puppy)
			// Set the logging level.
			handler.logLevel = .trace
			return handler
		}
		
		let logger = Logger(label: "TUICommand")
		
		logger.info("PATH       = \(Env.path().joined(separator: ":"))")
		logger.info("fileToOpen = \(fileToOpen ?? "NONE")")
		logger.info("clangd     = \(clangd)")
		logger.info("sourcekit  = \(sourcekit)")
		let textUserInterfaceApp = TextUserInterfaceApp()
		var startupStatus: String? = nil
		var documentURL: URL? = nil
		var initialBuffer = EditorBuffer()
		if let fileToOpen {
			let expandedPath = NSString(string: fileToOpen).expandingTildeInPath
			let url = URL(fileURLWithPath: expandedPath)
			documentURL = url
			if FileManager.default.fileExists(atPath: url.path) {
				do {
					let contents = try String(contentsOf: url, encoding: .utf8)
					initialBuffer = EditorBuffer(text: contents)
					startupStatus = "Opened \(url.lastPathComponent)"
				} catch {
					logger.error("Failed to open \(url.path): \(error.localizedDescription)")
					startupStatus = "Failed to open \(url.lastPathComponent): \(error.localizedDescription)"
				}
			} else {
				startupStatus = "New file \(url.lastPathComponent)"
			}
		}
		
		textUserInterfaceApp.run(
			buffer: initialBuffer,
			documentURL: documentURL,
			diagsProvider: nil,
			enableKeyInspector: inspectKeys,
			startupStatus: startupStatus
		)
	}
}
