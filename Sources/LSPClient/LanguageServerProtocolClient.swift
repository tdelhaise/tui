import Foundation
import NIO
import NIOPosix
import NIOFoundationCompat

public actor LanguageServerProtocolClient {
    public struct ServerConfig {
        public let executablePath: String
        public let arguments: [String]
        public init(executablePath: String, arguments: [String] = []) {
            self.executablePath = executablePath
            self.arguments = arguments
        }
    }

    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private var process: Process?
    private var stdinPipe = Pipe()
    private var stdoutPipe = Pipe()
	private(set) var buffer = Data()

    public init() {}

    public func start(config: ServerConfig) async throws {
        let processToRun = Process()
		processToRun.executableURL = URL(fileURLWithPath: config.executablePath)
		processToRun.arguments = config.arguments
		processToRun.standardInput = stdinPipe
		processToRun.standardOutput = stdoutPipe
		processToRun.standardError = FileHandle.standardError
        try processToRun.run()
        self.process = processToRun

        // Start reading stdout for JSON-RPC messages
		stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let copiedData = handle.availableData
			Task {
				if copiedData.count > 0 {
					await self.consume(data: copiedData)
				}
			}
        }

        // Send initialize later (caller can use send method)
    }

    public func stop() async {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
		try? await group.shutdownGracefully()
    }

    private func consume(data: Data) async {
        buffer.append(data)
        // Very simple header parsing (Content-Length). Robust impl should stream-parse.
        while true {
            guard let headerRange = buffer.range(of: Data("\r\n\r\n".utf8)) else {
				break
			}
            let headerData = buffer.subdata(in: 0..<headerRange.lowerBound)
            guard let headerStr = String(data: headerData, encoding: .utf8) else {
				break
			}
            var contentLength = 0
            for line in headerStr.split(separator: "\r\n") {
                let parts = line.split(separator: ":", maxSplits: 1).map {
					$0.trimmingCharacters(in: .whitespaces)
				}
                if parts.count == 2 && parts[0].lowercased() == "content-length" {
                    contentLength = Int(parts[1]) ?? 0
                }
            }
            let messageStart = headerRange.upperBound
            if buffer.count < messageStart + contentLength {
				break
			}
            let message = buffer.subdata(in: messageStart..<(messageStart + contentLength))
            await handleMessageData(message)
            buffer.removeSubrange(0..<(messageStart + contentLength))
        }
    }

    private func handleMessageData(_ data: Data) async {
        // For now, just log
        if let s = String(data: data, encoding: .utf8) {
            // fputs("[LSP <-] \(s)\n", stderr)
        }
    }

    public func send(json: [String: Any]) async {
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: []) else {
			return
		}
        let header = "Content-Length: \(data.count)\r\n\r\n"
        let headerData = header.data(using: .utf8)!
        stdinPipe.fileHandleForWriting.write(headerData)
        stdinPipe.fileHandleForWriting.write(data)
        // stdinPipe.fileHandleForWriting.synchronizeFile()
    }
}
