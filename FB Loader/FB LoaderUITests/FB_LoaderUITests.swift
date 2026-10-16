import XCTest

final class FBLoaderUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
    }

    @MainActor
    func testExample() throws {
        throw XCTSkip("Template UI smoke test is disabled until we have a deterministic fixture catalog.")
    }

    @MainActor
    func testLaunchPerformance() throws {
        throw XCTSkip("Template launch-performance test does not validate app behavior and is noisy for local runs.")
    }
}
