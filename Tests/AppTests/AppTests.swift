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
			let expected = NotificationPayload(title: "Hello", message: "world")
			let original = NotificationServices.shared()
			NotificationServices.overrideWith(DummyService(onPost: { payload in
				XCTAssertEqual(payload.title, expected.title)
				XCTAssertEqual(payload.message, expected.message)
			}))
			defer { NotificationServices.overrideWith(original) }
			NotificationServices.shared().post(expected)
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
