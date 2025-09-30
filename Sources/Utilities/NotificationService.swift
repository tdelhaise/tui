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
	func post(_ payload: NotificationPayload) {
		#if os(macOS)
			macOSPost(payload)
		#elseif os(Linux)
			linuxPost(payload)
		#else
			Log.info("Notification: \(payload.title) — \(payload.message)")
		#endif
	}
	
	#if os(macOS)
	private func macOSPost(_ payload: NotificationPayload) {
		// Placeholder until NSUserNotification/UNUserNotification integration lands.
		Log.info("macOS notification pending integration: \(payload.title) — \(payload.message)")
	}
	#endif
	
	#if os(Linux)
	private func linuxPost(_ payload: NotificationPayload) {
		// Placeholder until a D-Bus bridge is wired in.
		Log.info("Linux notification pending integration: \(payload.title) — \(payload.message)")
	}
	#endif
}

public struct LoggingNotificationService: NotificationService {
	public init() {}
	
	public func post(_ payload: NotificationPayload) {
		Log.info("NotificationFallback \(payload.kind): \(payload.title) — \(payload.message)")
	}
}
