import XCTest

/// Deleting a round from the list, on a store on disk that the app is
/// relaunched on.
@MainActor
final class RoundDeleteUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
    }

    /// Two rounds in a store on disk: a finished one that is seeded (18 holes,
    /// 3 players, 54 scores) and the sample round (18 holes, 4 players).
    func testDeletingARoundRemovesItFromTheListAndTheStore() throws {
        let store = ["-debugStoreFile", "ui-test-\(UUID().uuidString)", "-debugStoreCounts"]
        app.launchArguments = ["-debugSeedRound", "finalPush", "-debugCourseLookup", "off"] + store
        app.launch()

        XCTAssertTrue(element("detail.scoreRound").waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let seeded = element("rounds.row.Carryover Links")
        XCTAssertTrue(seeded.waitForExistence(timeout: 5))
        XCTAssertEqual(label(of: "debug.storeCounts"), "Stored: 1 rounds, 18 holes, 3 players, 54 scores")

        app.buttons["New round"].firstMatch.tap()
        XCTAssertTrue(app.textFields["setup.courseName"].waitForExistence(timeout: 5))
        app.buttons["Fill sample"].tap()
        app.buttons["Next"].tap()
        XCTAssertTrue(app.navigationBars["Players"].waitForExistence(timeout: 5))
        app.buttons["Next"].tap()
        XCTAssertTrue(app.navigationBars["Games"].waitForExistence(timeout: 5))
        app.buttons["Create"].tap()
        XCTAssertTrue(element("detail.scoreRound").waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let sample = element("rounds.row.Sample Links")
        XCTAssertTrue(sample.waitForExistence(timeout: 5))
        XCTAssertTrue(seeded.exists)
        XCTAssertEqual(label(of: "debug.storeCounts"), "Stored: 2 rounds, 36 holes, 7 players, 54 scores")
        attachScreenshot("50-rounds-before-delete")

        delete(seeded)
        XCTAssertTrue(sample.exists)
        XCTAssertEqual(label(of: "debug.storeCounts"), "Stored: 1 rounds, 18 holes, 4 players, 0 scores")
        attachScreenshot("51-rounds-after-delete")

        // A new launch reads the store from disk: the deleted round stays deleted.
        app.terminate()
        app.launchArguments = store
        app.launch()
        XCTAssertTrue(sample.waitForExistence(timeout: 10))
        XCTAssertFalse(seeded.exists)
        XCTAssertEqual(label(of: "debug.storeCounts"), "Stored: 1 rounds, 18 holes, 4 players, 0 scores")
        attachScreenshot("52-rounds-after-relaunch")

        delete(sample)
        XCTAssertTrue(app.staticTexts["No rounds yet"].waitForExistence(timeout: 5))
        XCTAssertEqual(label(of: "debug.storeCounts"), "Stored: 0 rounds, 0 holes, 0 players, 0 scores")
    }

    /// Deleting asks first: Cancel keeps the round, "Delete round" deletes it.
    private func delete(_ row: XCUIElement) {
        let confirmation = app.alerts["Delete this round?"]
        for answer in ["Cancel", "Delete round"] {
            row.swipeLeft()
            let delete = app.buttons["Delete"]
            XCTAssertTrue(appears(delete))
            delete.tap()
            XCTAssertTrue(appears(confirmation))
            XCTAssertTrue(row.exists)
            confirmation.buttons[answer].tap()
            XCTAssertTrue(disappears(confirmation))
        }
        XCTAssertTrue(disappears(row))
    }

    // MARK: Helpers

    /// `waitForExistence` without its delay for an element that is there already.
    private func appears(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        element.exists || element.waitForExistence(timeout: timeout)
    }

    private func disappears(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        !element.exists || element.waitForNonExistence(timeout: timeout)
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func label(of identifier: String) -> String {
        let element = element(identifier)
        XCTAssertTrue(appears(element), "\(identifier) not found")
        return element.label
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
