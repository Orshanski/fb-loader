//
//  FB_LoaderUITestsLaunchTests.swift
//  FB LoaderUITests
//
//  Created by Orshanski Alexey on 01.05.2026.
//

import XCTest

final class FB_LoaderUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        throw XCTSkip("Template launch screenshot test is disabled until UI tests configure a fixture catalog.")
    }
}
