import XCTest

/// Walks the main screens in the light and in the dark color scheme and
/// attaches a screenshot of each, to look at the design.
///
/// The rounds are the ones of `-debugSeedRound gallery` (DebugRounds): Morning
/// Links is being played, Sample Links is finished with every kind of score
/// and Carryover Links is finished with $20.00 of skins unresolved.
@MainActor
final class ThemeScreenshotsUITests: XCTestCase {
    private let app = XCUIApplication()
    private var scheme = "light"

    override func setUp() {
        continueAfterFailure = false
    }

    func testMainScreensInLight() throws {
        walk(scheme: "light")
    }

    func testMainScreensInDark() throws {
        walk(scheme: "dark")
    }

    private func walk(scheme: String) {
        self.scheme = scheme
        emptyListAndSetup()
        app.terminate()
        rounds()
    }

    /// The empty list, the placeholder tabs and the first step of the setup.
    private func emptyListAndSetup() {
        app.launchArguments = ["-inMemoryStore", "-debugColorScheme", scheme]
        app.launch()
        let newRound = app.buttons["New round"].firstMatch
        XCTAssertTrue(newRound.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["No rounds yet"].exists)
        attachScreenshot("rounds-empty")

        app.tabBars.buttons["Courses"].tap()
        XCTAssertTrue(app.staticTexts["Course search arrives in M2."].waitForExistence(timeout: 5))
        attachScreenshot("courses-placeholder")
        app.tabBars.buttons["Profile"].tap()
        XCTAssertTrue(app.staticTexts["Sign in and your handicap arrive in M1."].waitForExistence(timeout: 5))
        attachScreenshot("profile-placeholder")
        app.tabBars.buttons["Rounds"].tap()

        XCTAssertTrue(newRound.waitForExistence(timeout: 5))
        newRound.tap()
        XCTAssertTrue(app.textFields["setup.courseName"].waitForExistence(timeout: 5))
        app.buttons["Fill sample"].tap()
        XCTAssertTrue(waitUntil { self.app.textFields["setup.courseName"].value as? String == "Sample Links" })
        attachScreenshot("setup-course")
    }

    /// The list, a finished round from its scorecard to a payment, and the
    /// settlement with the unresolved carryover.
    private func rounds() {
        app.launchArguments = [
            "-inMemoryStore", "-debugSeedRound", "gallery", "-debugSeedStartedAt", "1790424000",
            "-debugLinkOpener", "opens", "-debugColorScheme", scheme,
        ]
        app.launch()
        let finished = element("rounds.row.Sample Links")
        XCTAssertTrue(finished.waitForExistence(timeout: 10))
        XCTAssertTrue(element("rounds.row.Morning Links").exists)
        XCTAssertTrue(element("rounds.row.Carryover Links").exists)
        XCTAssertTrue(app.staticTexts["In progress, through 7 holes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Final: Zach won $128.00"].waitForExistence(timeout: 5))
        attachScreenshot("rounds-list")

        // Round detail with the scorecard.
        finished.tap()
        XCTAssertTrue(element("detail.scoreRound").waitForExistence(timeout: 5))
        XCTAssertEqual(label(of: "detail.holesCompleted"), "Holes completed, 18 of 18")
        XCTAssertTrue(label(of: "scorecard.Out.Jo").hasPrefix("Jo, 4, 5, 2, 4, 4, 3, 3, 4, 4, 33"))
        attachScreenshot("round-detail-scorecard")

        // Hole 7, a par 5, has a birdie, a bogey, a double bogey and an eagle.
        element("detail.scoreRound").tap()
        XCTAssertEqual(label(of: "scoring.hole.title"), "Hole 18")
        for _ in 0..<11 { app.buttons["scoring.previous"].tap() }
        XCTAssertEqual(label(of: "scoring.hole.title"), "Hole 7")
        XCTAssertEqual(label(of: "scoring.hole.detail"), "Par 5 - Stroke index 9")
        XCTAssertTrue(app.staticTexts["Scores"].exists)
        XCTAssertEqual(app.buttons["score.value.Zach"].value as? String, "4")
        XCTAssertEqual(label(of: "score.notation.Zach"), "Birdie")
        XCTAssertEqual(label(of: "score.notation.Sam"), "Bogey")
        XCTAssertEqual(label(of: "score.notation.Alex"), "Double bogey")
        XCTAssertEqual(label(of: "score.notation.Jo"), "Eagle")
        attachScreenshot("scoring-hole-7-notation")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // The settlement and a payment.
        tapWhenThere("detail.settlement")
        XCTAssertTrue(app.navigationBars["Settlement"].waitForExistence(timeout: 5))
        XCTAssertTrue(label(of: "settlement.status").hasPrefix("Final"))
        let payment = element("settlement.payment.1")
        XCTAssertTrue(payment.waitForExistence(timeout: 5))
        XCTAssertFalse(element("settlement.carryover").exists)
        attachScreenshot("settlement-headline")
        payment.tap()
        XCTAssertTrue(element("payment.summary").waitForExistence(timeout: 5))
        XCTAssertEqual(label(of: "payment.state"), "Not paid")
        attachScreenshot("payment-sheet")
        app.buttons["payment.done"].tap()

        // The unresolved carryover.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element("detail.scoreRound").waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        tapWhenThere("rounds.row.Carryover Links")
        tapWhenThere("detail.settlement")
        let carryover = label(of: "settlement.carryover")
        XCTAssertTrue(carryover.hasPrefix("$20.00 skins carryover is unresolved"))
        XCTAssertTrue(carryover.contains("NOT paid out"))
        XCTAssertTrue(carryover.contains("awaiting a rules decision"))
        XCTAssertEqual(label(of: "settlement.payment.1"), "Alex pays Zach $67.00")
        attachScreenshot("settlement-carryover")
    }

    // MARK: Helpers

    private func tapWhenThere(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let element = element(identifier)
        XCTAssertTrue(
            waitUntil { element.exists && element.isHittable },
            "\(identifier) is not on screen",
            file: file,
            line: line
        )
        element.tap()
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: @escaping () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func label(of identifier: String) -> String {
        let element = element(identifier)
        XCTAssertTrue(element.exists || element.waitForExistence(timeout: 5), "\(identifier) not found")
        return element.label
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "theme-\(name)-\(scheme)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
