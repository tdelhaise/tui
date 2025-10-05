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
		
		/*
		let languageServerProtocolClient = LanguageServerProtocolClient()
		
		// Try to start clangd (non-fatal if missing)
		if FileManager.default.fileExists(atPath: clangd) {
			try? await languageServerProtocolClient.start(config: .init(executablePath: clangd, arguments: []))
			// Minimal initialize (not complete)
			let initMsg: [String: Any] = [
				"jsonrpc": "2.0",
				"id": 1,
				"method": "initialize",
				"params": [
					"processId": ProcessInfo.processInfo.processIdentifier,
					"rootUri": URL(fileURLWithPath: FileManager.default.currentDirectoryPath).absoluteString,
					"capabilities": [:]
				]
			]
			await languageServerProtocolClient.send(json: initMsg)
		} else {
			Log.warn("clangd not found at \(clangd) — LSP C/C++ disabled for this run")
		}
		*/
		let newEditorBuffer = EditorBuffer.init()
		
		textUserInterfaceApp.run(buffer: newEditorBuffer, diagsProvider: nil, enableKeyInspector: inspectKeys)
	}
}
