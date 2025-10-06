import Foundation
import XCTest

@MainActor
private final class MainActorResultBox {
	var result: Result<Void, Error>?
}

internal extension XCTestCase {
	func runOnMainActor(description: String, timeout: TimeInterval = 2.0, _ operation: @escaping @MainActor () throws -> Void) throws {
		let expectation = expectation(description: description)
		let box = MainActorResultBox()
		Task { @MainActor in
			box.result = Result { try operation() }
			expectation.fulfill()
		}
		wait(for: [expectation], timeout: timeout)
		let result = MainActor.assumeIsolated { box.result }
		switch result {
		case .success?:
			break
		case .failure(let error)?:
			throw error
		case nil:
			XCTFail("Main actor operation \(description) did not complete")
		}
	}
}
