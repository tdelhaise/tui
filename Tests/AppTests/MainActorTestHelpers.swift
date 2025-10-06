import XCTest
import Atomics

internal extension XCTestCase {
	func runOnMainActor(description: String, timeout: TimeInterval = 2.0, _ operation: @escaping @MainActor () throws -> Void) throws {
		let completion = expectation(description: description)
		let result = ManagedAtomic<Result<Void, Error>?>(nil)
		Task { @MainActor in
			let outcome: Result<Void, Error>
			do {
				try operation()
				outcome = .success(())
			} catch {
				outcome = .failure(error)
			}
			result.store(outcome, ordering: .relaxed)
			completion.fulfill()
		}
		wait(for: [completion], timeout: timeout)
		switch result.load(ordering: .relaxed) {
		case .success?:
			break
		case .failure(let error)?:
			throw error
		case nil:
			XCTFail("Main actor operation \(description) did not complete")
		}
	}
}
