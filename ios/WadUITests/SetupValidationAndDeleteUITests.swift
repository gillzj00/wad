import XCTest

/// What the group sees when a setup step has problems, and deleting a round
/// from the list. Driven by tapping and typing, like the walkthrough.
@MainActor
final class SetupValidationAndDeleteUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: Course

    func testCourseStepShowsWhatToFixAndDoesNotMoveOn() throws {
        app.launchArguments = ["-inMemoryStore"]
        app.launch()
        let newRound = app.buttons["New round"].firstMatch
        XCTAssertTrue(newRound.waitForExistence(timeout: 10))
        newRound.tap()
        XCTAssertTrue(app.textFields["setup.courseName"].waitForExistence(timeout: 5))
        XCTAssertFalse(element("setup.issue.1").exists)

        // No name, a rating without a slope and no stroke indexes.
        replaceText(in: app.textFields["Rating"], with: "72.5")
        advance(staysOn: "Course", issues: [
            "Enter the course name.",
            "Enter both the rating and the slope, or leave both blank.",
            "Stroke index missing on holes " + (1...18).map(String.init).joined(separator: ", ") + ".",
        ])
        attachScreenshot("40-setup-course-issues")

        // The sample course has all of them.
        app.buttons["Fill sample"].tap()
        expectNoIssues()

        // Hole 18 gets the stroke index of hole 17.
        let strokeIndex = app.textFields["setup.hole.18.strokeIndex"]
        XCTAssertEqual(app.textFields["setup.hole.17.strokeIndex"].value as? String, "4")
        replaceText(in: strokeIndex, with: "4")
        advance(staysOn: "Course", issues: ["Stroke index 4 is used on holes 17, 18."])
        replaceText(in: strokeIndex, with: "")
        advance(staysOn: "Course", issues: ["Stroke index missing on hole 18."])

        // Fixed: the flow moves on.
        replaceText(in: strokeIndex, with: "14")
        expectNoIssues()
        app.buttons["Next"].tap()
        XCTAssertTrue(app.navigationBars["Players"].waitForExistence(timeout: 5))
        XCTAssertFalse(element("setup.issue.1").exists)
    }

    // MARK: Players and games

    func testPlayersAndGamesStepsShowWhatToFixAndDoNotMoveOn() throws {
        // The sample draft: Zach, Sam, Alex and Jo on a course with a rating and slope.
        app.launchArguments = ["-inMemoryStore", "-debugSetupStep", "players"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Players"].waitForExistence(timeout: 10))

        let name = app.textFields["setup.player.1.name"]
        let handicapIndex = app.textFields["setup.player.1.handicapIndex"]
        let playerOneIssues = [
            "Player 1: enter a name.",
            "Player 1: the handicap index is a number up to 54.0, such as 15.4 (or +1.2).",
        ]

        // No name, a handicap index over 54 and the name of the third player.
        replaceText(in: name, with: "", submits: true)
        replaceText(in: handicapIndex, with: "99", submits: true)
        replaceText(in: app.textFields["setup.player.2.name"], with: "Alex", submits: true)
        advance(staysOn: "Players", issues: playerOneIssues + ["More than one player is named Alex."])
        attachScreenshot("41-setup-players-issues")

        // A round has 2 to 4 players: no fifth player, and no way below two.
        let add = app.buttons["setup.addPlayer"]
        reach(add, swiping: .down)
        XCTAssertFalse(add.isEnabled)
        let removeFourth = app.buttons["setup.player.4.remove"]
        reach(removeFourth, swiping: .down)
        removeFourth.tap()
        XCTAssertTrue(disappears(removeFourth))
        XCTAssertTrue(add.isEnabled)
        let removeThird = app.buttons["setup.player.3.remove"]
        reach(removeThird, swiping: .down)
        removeThird.tap()
        XCTAssertTrue(disappears(app.textFields["setup.player.3.name"]))
        reach(name, swiping: .down)
        reach(add, swiping: .up)
        for player in 1...4 {
            XCTAssertFalse(app.buttons["setup.player.\(player).remove"].exists)
        }
        // Alex was removed, so the name is no longer used twice.
        advance(staysOn: "Players", issues: playerOneIssues)
        attachScreenshot("42-setup-players-two-left")

        // Fixed: the flow moves on.
        replaceText(in: name, with: "Zach", swiping: .down, submits: true)
        replaceText(in: handicapIndex, with: "15.4", swiping: .down, submits: true)
        expectNoIssues()
        app.buttons["Next"].tap()
        XCTAssertTrue(app.navigationBars["Games"].waitForExistence(timeout: 5))

        // Games: an amount with three decimal places.
        let skins = app.textFields["setup.amount.skins"]
        replaceText(in: skins, with: "7.505")
        advance(with: "Create", staysOn: "Games", issues: ["Skins: enter dollars and cents, such as 7 or 7.50."])
        attachScreenshot("43-setup-games-issues")

        // Fixed: the round is created with the two players.
        replaceText(in: skins, with: "7.50")
        expectNoIssues()
        app.buttons["Create"].tap()
        XCTAssertTrue(element("detail.scoreRound").waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Sample Links"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element("rounds.row.Sample Links").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Zach, Alex"].exists)
    }

    // MARK: Delete

    /// Two rounds in a store on disk: a finished one that is seeded (18 holes,
    /// 3 players, 54 scores) and the sample round (18 holes, 4 players).
    func testDeletingARoundRemovesItFromTheListAndTheStore() throws {
        let store = ["-debugStoreFile", "ui-test-\(UUID().uuidString)", "-debugStoreCounts"]
        app.launchArguments = ["-debugSeedRound", "finalPush"] + store
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

    private func delete(_ row: XCUIElement) {
        row.swipeLeft()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(appears(delete))
        delete.tap()
        XCTAssertTrue(disappears(row))
    }

    // MARK: Helpers

    /// The way to swipe for an element that is off screen: up for one further
    /// down the list, down for one further up.
    private enum Swipe { case up, down }

    /// Tries to move on and expects to stay on the step with exactly these
    /// messages on screen, without scrolling to them.
    private func advance(
        with button: String = "Next",
        staysOn step: String,
        issues: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        app.buttons[button].tap()
        for (offset, message) in issues.enumerated() {
            let issue = element("setup.issue.\(offset + 1)")
            XCTAssertTrue(appears(issue), "\(message) is not shown", file: file, line: line)
            XCTAssertEqual(issue.label, message, file: file, line: line)
            XCTAssertTrue(waitUntil { issue.isHittable }, "\(message) is off screen", file: file, line: line)
        }
        XCTAssertFalse(element("setup.issue.\(issues.count + 1)").exists, file: file, line: line)
        XCTAssertTrue(app.navigationBars[step].exists, "left the \(step) step", file: file, line: line)
    }

    private func expectNoIssues(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(disappears(element("setup.issue.1")), file: file, line: line)
        XCTAssertFalse(app.staticTexts["To fix"].exists, file: file, line: line)
    }

    /// Replaces what the field holds by typing.
    private func replaceText(
        in field: XCUIElement,
        with text: String,
        swiping swipe: Swipe? = nil,
        submits: Bool = false
    ) {
        reach(field, swiping: swipe)
        // The keyboard moves the list, so the field has the focus before it is tapped again.
        field.tap()
        XCTAssertTrue(waitUntil { self.app.keyboards.firstMatch.exists }, "no keyboard for \(field)")
        // Where one tap puts the cursor varies; three taps select everything the field holds.
        field.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        app.typeText(text.isEmpty ? XCUIKeyboardKey.delete.rawValue : text)
        XCTAssertEqual(field.value as? String, text.isEmpty ? field.placeholderValue : text)
        if submits { app.typeText("\n") } else { dismissKeyboard() }
    }

    /// The number pads have no return key; the course step has a Done button
    /// above them. The list does not scroll away from the field that has the focus.
    private func dismissKeyboard() {
        let done = app.toolbars.buttons.matching(identifier: "Done").allElementsBoundByIndex.first { $0.isHittable }
        guard let done else { return }
        done.tap()
        XCTAssertTrue(disappears(app.keyboards.firstMatch))
    }

    /// Swipes the list until the element can be tapped. Without a way to swipe
    /// the element is expected on screen.
    private func reach(_ element: XCUIElement, swiping swipe: Swipe?) {
        guard let swipe else {
            // Rows appear a moment after a screen or the keyboard changes.
            XCTAssertTrue(waitUntil { element.exists && element.isHittable }, "\(element) is not on screen")
            return
        }
        let list = app.collectionViews.firstMatch
        for _ in 0..<10 {
            if element.exists, element.isHittable { return }
            // The upper part of the list, which the keyboard does not cover, and the
            // margin beside the rows, where a drag does not move a control.
            let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: swipe == .up ? 0.5 : 0.2))
            let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: swipe == .up ? 0.2 : 0.5))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(element.exists && element.isHittable, "\(element) cannot be reached")
    }

    /// `waitForExistence` without its delay for an element that is there already.
    private func appears(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        element.exists || element.waitForExistence(timeout: timeout)
    }

    private func disappears(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        !element.exists || element.waitForNonExistence(timeout: timeout)
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
