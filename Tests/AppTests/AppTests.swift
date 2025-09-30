import XCTest
@testable import App
@testable import Utilities

final class AppTests: XCTestCase {
    func testExample() {
        XCTAssertTrue(true)
    }

    @MainActor
    func testNotificationServiceOverride() {
        struct DummyService: NotificationService {
            let onPost: (NotificationPayload) -> Void
            func post(_ payload: NotificationPayload) {
                onPost(payload)
            }
        }
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
