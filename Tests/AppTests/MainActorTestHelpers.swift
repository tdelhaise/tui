import XCTest

internal extension XCTestCase {
	func runOnMainActor(description: String, timeout: TimeInterval = 2.0, _ operation: @escaping @MainActor () throws -> Void) throws {
		let completion = expectation(description: description)
		var result: Result<Void, Error>?
		Task { @MainActor in
			do {
				try operation()
				result = .success(())
			} catch {
				result = .failure(error)
			}
			completion.fulfill()
		}
		wait(for: [completion], timeout: timeout)
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
