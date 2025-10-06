import XCTest
@testable import App
@testable import Utilities

final class AppTests: XCTestCase {
    func testExample() {
        XCTAssertTrue(true)
    }

	func testNotificationServiceOverride() {
		struct DummyService: NotificationService {
			let onPost: @Sendable (NotificationPayload) -> Void
			func post(_ payload: NotificationPayload) {
				onPost(payload)
			}
		}

		runOnMainActor(description: "override notification service") {
			var received: NotificationPayload?
			let original = NotificationServices.shared()
			NotificationServices.overrideWith(DummyService(onPost: { payload in
				received = payload
			}))
			defer { NotificationServices.overrideWith(original) }
			NotificationServices.shared().post(.init(title: "Hello", message: "world"))
			XCTAssertEqual(received?.title, "Hello")
			XCTAssertEqual(received?.message, "world")
		}
	}
}

private extension XCTestCase {
	func runOnMainActor(description: String, timeout: TimeInterval = 2.0, _ operation: @escaping @MainActor () -> Void) {
		let completion = expectation(description: description)
		Task { @MainActor in
			operation()
			completion.fulfill()
		}
		wait(for: [completion], timeout: timeout)
	}
}
