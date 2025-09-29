import Foundation
import ArgumentParser
import LSPClient
import Utilities
import TextUserInterfaceApp
import Editors

@MainActor
struct TUICommand: AsyncParsableCommand {
	
	@Option(name: .shortAndLong, help: "Path to clangd (for C/C++).")
	var clangd: String = (["/opt/homebrew/bin/clangd","/usr/local/bin/clangd","/usr/bin/clangd"].first { FileManager.default.fileExists(atPath: $0) }) ?? "/usr/bin/clangd"
	
	@Option(name: .shortAndLong, help: "Path to sourcekit-lsp (for Swift).")
	var sourcekit: String = (["/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/sourcekit-lsp","/usr/bin/sourcekit-lsp","/opt/homebrew/bin/sourcekit-lsp","/usr/local/bin/sourcekit-lsp"].first { FileManager.default.fileExists(atPath: $0) }) ?? "/usr/bin/sourcekit-lsp"

	mutating func run() async throws {
		Log.info("PATH=\(Env.path().joined(separator: ":"))")
		let textUserInterfaceApp = TextUserInterfaceApp()
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
		
		let newEditorBuffer = EditorBuffer.init()
		
		textUserInterfaceApp.run(buffer: newEditorBuffer,diagsProvider: nil)
	}
}
