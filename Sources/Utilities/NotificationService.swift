import Foundation

public struct NotificationPayload: Sendable {
	public enum Kind: Sendable {
		case info
		case success
		case warning
		case error
	}
	
	public var title: String
	public var message: String
	public var kind: Kind
	public var metadata: [String: String]
	
	public init(title: String, message: String, kind: Kind = .info, metadata: [String: String] = [:]) {
		self.title = title
		self.message = message
		self.kind = kind
		self.metadata = metadata
	}
}

private extension NotificationPayload.Kind {
	var label: String {
		switch self {
		case .info: return "info"
		case .success: return "success"
		case .warning: return "warning"
		case .error: return "error"
		}
	}
}

@MainActor
public protocol NotificationService: Sendable {
	func post(_ payload: NotificationPayload)
}

@MainActor
public enum NotificationServices {
	private static var service: NotificationService = PlatformNotificationService()
	
	public static func shared() -> NotificationService {
		service
	}
	
	public static func overrideWith(_ newService: NotificationService) {
		service = newService
	}
}

struct PlatformNotificationService: NotificationService {
	private static let capabilities = NotificationCapabilities.detect()

	func post(_ payload: NotificationPayload) {
		#if os(macOS)
			if let executable = Self.capabilities.appleScriptExecutable {
				if macOSPost(payload, executable: executable) { return }
			} else {
				Log.info("Notification shim disabled: osascript unavailable")
			}
			Log.info("Notification (macOS fallback): \(payload.title) - \(payload.message)")
		#elseif os(Linux)
			if let executable = Self.capabilities.notifySendCommand {
				if linuxPost(payload, executable: executable) { return }
			} else {
				Log.info("Notification shim disabled: notify-send unavailable")
			}
			Log.info("Notification (Linux fallback): \(payload.title) - \(payload.message)")
		#else
			Log.info("Notification: \(payload.title) - \(payload.message)")
		#endif
	}
	
	#if os(macOS)
	private func macOSPost(_ payload: NotificationPayload, executable: String) -> Bool {
		let script = "display notification \"\(escapeAppleScript(composedMessage(from: payload)))\" with title \"\(escapeAppleScript(payload.title))\""
		return runProcess(executable: executable, arguments: ["-e", script], payload: payload)
	}

	private func escapeAppleScript(_ value: String) -> String {
		value
			.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: "\"", with: "\\\"")
			.replacingOccurrences(of: "\n", with: " ")
	}
	#endif

	#if os(Linux)
	private func linuxPost(_ payload: NotificationPayload, executable: String) -> Bool {
		let message = composedMessage(from: payload)
		return runProcess(executable: executable, arguments: [payload.title, message], payload: payload)
	}
	#endif
	
	private func composedMessage(from payload: NotificationPayload) -> String {
		var parts: [String] = []
		if !payload.message.isEmpty {
			parts.append(payload.message)
		}
		if !payload.metadata.isEmpty {
			let meta = payload.metadata
				.sorted { $0.key < $1.key }
				.map { "\($0.key)=\($0.value)" }
				.joined(separator: " ")
			parts.append(meta)
		}
		if parts.isEmpty {
			parts.append(payload.kind.label.capitalized)
		}
		return parts.joined(separator: "\n")
	}

	private func runProcess(executable: String, arguments: [String], payload: NotificationPayload) -> Bool {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: executable)
		process.arguments = arguments
		do {
			try process.run()
			process.waitUntilExit()
			if process.terminationStatus != 0 {
				Log.warn("Notification command failed (code: \(process.terminationStatus)) for \(payload.title)")
				return false
			}
			return true
		} catch {
			Log.warn("Notification command failed for \(payload.title): \(error)")
			return false
		}
	}
}

private struct NotificationCapabilities {
#if os(macOS)
	let appleScriptExecutable: String?

	static func detect() -> NotificationCapabilities {
		let path = findExecutable(named: "osascript", preferred: "/usr/bin/osascript")
		return NotificationCapabilities(appleScriptExecutable: path)
	}
#elseif os(Linux)
	let notifySendCommand: String?

	static func detect() -> NotificationCapabilities {
		let env = ProcessInfo.processInfo.environment
		let hasDisplay = env["DISPLAY"] != nil || env["WAYLAND_DISPLAY"] != nil
		let hasBus = env["DBUS_SESSION_BUS_ADDRESS"] != nil || env["DBUS_STARTER_ADDRESS"] != nil
		guard hasDisplay || hasBus else { return NotificationCapabilities(notifySendCommand: nil) }
		let path = findExecutable(named: "notify-send")
		return NotificationCapabilities(notifySendCommand: path)
	}
#else
	static func detect() -> NotificationCapabilities {
		NotificationCapabilities()
	}
#endif
}

#if os(macOS) || os(Linux)
private extension NotificationCapabilities {
	static func findExecutable(named name: String, preferred: String? = nil) -> String? {
		let fm = FileManager.default
		if let preferred, fm.isExecutableFile(atPath: preferred) {
			return preferred
		}
		for directory in Env.path() {
			let candidate = (directory as NSString).appendingPathComponent(name)
			if fm.isExecutableFile(atPath: candidate) {
				return candidate
			}
		}
		return nil
	}
}
#endif

public struct LoggingNotificationService: NotificationService {
	public init() {}

	public func post(_ payload: NotificationPayload) {
		Log.info("NotificationFallback \(payload.kind): \(payload.title) - \(payload.message)")
	}
}
