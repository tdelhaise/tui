import Foundation
import XCTest

internal extension XCTestCase {
	func runOnMainActor(description: String, timeout: TimeInterval = 2.0, _ operation: @escaping @MainActor () throws -> Void) throws {
		final class OutcomeBox: @unchecked Sendable {
			var result: Result<Void, Error>?
		}

		let expectation = expectation(description: description)
		let box = OutcomeBox()
		Task { @MainActor in
			box.result = Result { try operation() }
			expectation.fulfill()
		}
		wait(for: [expectation], timeout: timeout)
		switch box.result {
		case .success?:
			break
		case .failure(let error)?:
			throw error
		case nil:
			XCTFail("Main actor operation \(description) did not complete")
		}
	}
}
