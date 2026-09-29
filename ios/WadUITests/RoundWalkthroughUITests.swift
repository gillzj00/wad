import XCTest

/// Sets up a round and scores its first holes the way a user does, by tapping
/// and typing, on an empty in-memory store. Attaches a screenshot of each screen.
@MainActor
final class RoundWalkthroughUITests: XCTestCase {
    private let app = XCUIApplication()
    private let courseName = "Walkthrough Links"
    private let players = [("Zach", "15"), ("Sam", "7"), ("Alex", "7")]

    func testSetsUpARoundAndScoresTheFirstHoles() throws {
        continueAfterFailure = false
        app.launchArguments = ["-inMemoryStore"]
        app.launch()

        // Rounds, empty.
        let newRound = app.buttons["New round"].firstMatch
        XCTAssertTrue(newRound.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["No rounds yet"].exists)
        attachScreenshot("01-rounds-empty")
        newRound.tap()

        setUpCourse()
        setUpPlayers()

        // Games: the default amounts.
        XCTAssertTrue(app.navigationBars["Games"].waitForExistence(timeout: 5))
        attachScreenshot("04-setup-games")
        app.buttons["Create"].tap()

        // Round detail.
        let scoreRound = element("detail.scoreRound")
        XCTAssertTrue(scoreRound.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars[courseName].exists)
        XCTAssertEqual(label(of: "detail.holesCompleted"), "Holes completed, 0 of 18")
        attachScreenshot("05-round-detail-new")
        scoreRound.tap()

        scoreHole1()
        scoreHole2()
        scoreHole3()

        // Back to the round: progress and scorecard.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element("detail.scoreRound").waitForExistence(timeout: 5))
        XCTAssertEqual(label(of: "detail.holesCompleted"), "Holes completed, 3 of 18")
        XCTAssertTrue(element("scorecard.Out.Zach").label.hasPrefix("Zach, 5, 4, 3, -, -, -, -, -, -, 12"))
        attachScreenshot("12-round-detail-progress")

        // Back to the list: the round is there.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let row = element("rounds.row.\(courseName)")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[courseName].exists)
        XCTAssertTrue(app.staticTexts["Zach, Sam, Alex"].exists)
        attachScreenshot("13-rounds-list")
    }

    // MARK: Setup

    private func setUpCourse() {
        let name = app.textFields["setup.courseName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(courseName + "\n")

        // Pars default to 4; the third hole is a par 3.
        let par = app.segmentedControls["setup.hole.3.par"]
        scrollTo(par)
        par.buttons["3"].tap()

        app.buttons["setup.strokeIndexes"].tap()
        let inOrder = app.buttons["Number 1 to 18 in order"]
        XCTAssertTrue(inOrder.waitForExistence(timeout: 5))
        inOrder.tap()
        attachScreenshot("02-setup-course")

        app.buttons["Next"].tap()
    }

    private func setUpPlayers() {
        XCTAssertTrue(app.navigationBars["Players"].waitForExistence(timeout: 5))
        for (offset, player) in players.enumerated() {
            let number = offset + 1
            let name = app.textFields["setup.player.\(number).name"]
            if !name.exists {
                let add = app.buttons["Add player"]
                scrollTo(add)
                add.tap()
            }
            scrollTo(name)
            name.tap()
            name.typeText(player.0 + "\n")

            let handicap = app.textFields["setup.player.\(number).courseHandicap"]
            scrollTo(handicap)
            handicap.tap()
            handicap.typeText(player.1 + "\n")
        }
        attachScreenshot("03-setup-players")
        app.buttons["Next"].tap()
    }

    // MARK: Scoring

    /// Par 4, stroke index 1: Zach's 5 nets 4 and ties the 4s. Sam, then Zach, make a Wad putt.
    private func scoreHole1() {
        XCTAssertTrue(element("scoring.hole.title").waitForExistence(timeout: 5))
        XCTAssertEqual(label(of: "scoring.hole.title"), "Hole 1")
        XCTAssertEqual(label(of: "scoring.hole.detail"), "Par 4 - Stroke index 1")
        XCTAssertEqual(app.buttons["score.value.Zach"].value as? String, "Not set")
        attachScreenshot("06-hole-1-empty")

        app.buttons["score.plus.Zach"].tap()
        app.buttons["score.plus.Zach"].tap()
        app.buttons["score.plus.Sam"].tap()
        app.buttons["score.minus.Alex"].tap()
        XCTAssertEqual(app.buttons["score.value.Zach"].value as? String, "5")
        XCTAssertEqual(app.buttons["score.value.Sam"].value as? String, "4")
        XCTAssertEqual(app.buttons["score.value.Alex"].value as? String, "4")
        XCTAssertEqual(label(of: "score.detail.Zach"), "1 tick, Net 4")
        XCTAssertEqual(label(of: "score.detail.Sam"), "No ticks, Net 4")

        // Clearing a score and entering it again.
        app.buttons["score.clear.Alex"].tap()
        XCTAssertEqual(app.buttons["score.value.Alex"].value as? String, "Not set")
        app.buttons["score.value.Alex"].tap()
        XCTAssertEqual(app.buttons["score.value.Alex"].value as? String, "4")

        tap("wad.maker.Sam")
        tap("wad.maker.Zach")
        XCTAssertEqual(app.buttons["wad.maker.Sam"].value as? String, "Make 1")
        XCTAssertEqual(app.buttons["wad.maker.Zach"].value as? String, "Make 2")
        XCTAssertEqual(app.buttons["wad.maker.Alex"].value as? String, "No make")

        XCTAssertTrue(label(of: "status.wad").hasPrefix("Zach holds the Wad at $9.00"))
        attachScreenshot("07-hole-1-scored")
        scrollTo(element("status.skins"))
        XCTAssertTrue(label(of: "status.skins").hasPrefix("Pushed"))
        XCTAssertTrue(label(of: "status.skins").contains("$5.00 carries to hole 2"))
        attachScreenshot("07-hole-1-games")

        app.buttons["scoring.next"].tap()
    }

    /// Par 4, stroke index 2: everyone makes 4, Zach's tick wins the carried skin.
    private func scoreHole2() {
        XCTAssertEqual(label(of: "scoring.hole.title"), "Hole 2")
        tap("scoring.parForRest")
        XCTAssertEqual(app.buttons["score.value.Zach"].value as? String, "4")
        XCTAssertEqual(label(of: "score.detail.Zach"), "1 tick, Net 3")
        XCTAssertTrue(label(of: "status.wad").hasPrefix("Zach holds the Wad at $9.00"))
        scrollTo(element("status.skins"))
        XCTAssertTrue(label(of: "status.skins").hasPrefix("Zach wins $10.00 from each other player"))
        attachScreenshot("08-hole-2-scored")

        app.buttons["scoring.next"].tap()
    }

    /// Par 3: Sam's 3 wins the greenie. Alex's 4 is not offered.
    private func scoreHole3() {
        XCTAssertEqual(label(of: "scoring.hole.title"), "Hole 3")
        XCTAssertEqual(label(of: "scoring.hole.detail"), "Par 3 - Stroke index 3")

        app.buttons["score.plus.Zach"].tap()
        app.buttons["score.plus.Sam"].tap()
        app.buttons["score.plus.Alex"].tap()
        app.buttons["score.plus.Alex"].tap()
        XCTAssertEqual(app.buttons["score.value.Alex"].value as? String, "4")

        tap("wad.maker.Alex")
        XCTAssertTrue(label(of: "status.wad").hasPrefix("Alex holds the Wad at $11.00"))

        scrollTo(app.buttons["greenie.option.none"])
        XCTAssertTrue(app.buttons["greenie.option.Zach"].exists)
        XCTAssertTrue(app.buttons["greenie.option.Sam"].exists)
        XCTAssertFalse(app.buttons["greenie.option.Alex"].exists)
        tap("greenie.option.Sam")
        XCTAssertTrue(label(of: "status.greenie").hasPrefix("Sam wins the greenie"))
        attachScreenshot("09-hole-3-greenie")

        // Sam's score is corrected to a 4: the greenie is flagged and not paid.
        scrollTo(app.buttons["score.plus.Sam"], direction: .down)
        app.buttons["score.plus.Sam"].tap()
        scrollTo(element("status.greenie"))
        XCTAssertTrue(label(of: "status.greenie").hasPrefix("Not paid: Sam did not score par or better"))
        XCTAssertFalse(app.buttons["greenie.option.Sam"].exists)
        attachScreenshot("10-hole-3-greenie-invalid")

        // Fixed by putting the score back.
        scrollTo(app.buttons["score.minus.Sam"], direction: .down)
        app.buttons["score.minus.Sam"].tap()
        scrollTo(element("status.greenie"))
        XCTAssertTrue(label(of: "status.greenie").hasPrefix("Sam wins the greenie"))

        scrollTo(element("scoring.hole.title"), direction: .down)
        attachScreenshot("11-hole-3-scored")
    }

    // MARK: Helpers

    private enum Direction { case up, down }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func label(of identifier: String) -> String {
        let element = element(identifier)
        XCTAssertTrue(element.waitForExistence(timeout: 5), "\(identifier) not found")
        return element.label
    }

    private func tap(_ identifier: String) {
        let button = app.buttons[identifier]
        scrollTo(button)
        button.tap()
    }

    /// Swipes the screen's list until the element can be tapped.
    private func scrollTo(_ element: XCUIElement, direction: Direction = .up) {
        let list = app.collectionViews.firstMatch
        for _ in 0..<8 {
            if isReachable(element) { break }
            let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: direction == .up ? 0.6 : 0.4))
            let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: direction == .up ? 0.3 : 0.7))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(isReachable(element), "\(element) cannot be reached")
    }

    /// On screen, and not under the scoring screen's bottom bar.
    private func isReachable(_ element: XCUIElement) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let next = app.buttons["scoring.next"]
        return !next.exists || element.frame.maxY <= next.frame.minY - 8
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
