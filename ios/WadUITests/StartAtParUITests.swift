import XCTest

/// A round created with "Start every hole at par": every player has par on
/// every hole from the start, the steppers move from it and the round detail
/// shows a scorecard full of pars. In the light and in the dark color scheme,
/// with a screenshot of each screen (named `par-<screen>-<light|dark>`).
@MainActor
final class StartAtParUITests: XCTestCase {
    private let app = XCUIApplication()
    private var scheme = "light"

    override func setUp() {
        continueAfterFailure = false
    }

    func testStartsEveryHoleAtParInLight() throws {
        walk(scheme: "light")
    }

    func testStartsEveryHoleAtParInDark() throws {
        walk(scheme: "dark")
    }

    /// The sample draft opened on the games step: Zach, Sam, Alex and Jo on
    /// Sample Links, whose first holes are a par 4, a par 5 and a par 3.
    private func walk(scheme: String) {
        self.scheme = scheme
        app.launchArguments = ["-inMemoryStore", "-debugSetupStep", "games", "-debugColorScheme", scheme]
        app.launch()

        // The sample draft leaves the holes unscored; the setting is turned on here.
        XCTAssertTrue(app.navigationBars["Games"].waitForExistence(timeout: 10))
        let startsAtPar = app.switches["setup.startsAtPar"].firstMatch
        XCTAssertTrue(startsAtPar.waitForExistence(timeout: 5))
        XCTAssertEqual(startsAtPar.value as? String, "0")
        flip(startsAtPar)
        XCTAssertTrue(waitUntil { startsAtPar.value as? String == "1" }, startsAtPar.debugDescription)
        attachScreenshot("setup-games")
        app.buttons["Create"].tap()

        // The round detail: every hole is complete and the scorecard is pars.
        let scoreRound = element("detail.scoreRound")
        XCTAssertTrue(scoreRound.waitForExistence(timeout: 5))
        XCTAssertEqual(label(of: "detail.holesCompleted"), "Holes completed, 18 of 18")
        XCTAssertTrue(app.staticTexts["Settlement"].exists)
        XCTAssertFalse(app.staticTexts["Settlement (provisional)"].exists)
        XCTAssertTrue(label(of: "scorecard.Out.Zach").hasPrefix("Zach, 4, 5, 3, 4, 4, 3, 5, 4, 4, 36"))
        XCTAssertTrue(label(of: "scorecard.Out.Jo").hasPrefix("Jo, 4, 5, 3, 4, 4, 3, 5, 4, 4, 36"))
        attachScreenshot("round-detail")

        // Hole 1, a par 4: everybody has 4, and the steppers move from it.
        scoreRound.tap()
        XCTAssertTrue(element("scoring.hole.title").waitForExistence(timeout: 5))
        XCTAssertEqual(label(of: "scoring.hole.title"), "Hole 1")
        XCTAssertEqual(label(of: "scoring.hole.detail"), "Par 4 - Stroke index 7")
        for name in ["Zach", "Sam", "Alex", "Jo"] {
            XCTAssertEqual(app.buttons["score.value.\(name)"].value as? String, "4")
            XCTAssertEqual(label(of: "score.notation.\(name)"), "Par")
        }
        XCTAssertFalse(app.buttons["scoring.parForRest"].exists)
        attachScreenshot("hole-1-pars")

        app.buttons["score.plus.Zach"].tap()
        XCTAssertEqual(app.buttons["score.value.Zach"].value as? String, "5")
        XCTAssertEqual(label(of: "score.notation.Zach"), "Bogey")
        app.buttons["score.minus.Sam"].tap()
        XCTAssertEqual(app.buttons["score.value.Sam"].value as? String, "3")
        XCTAssertEqual(label(of: "score.notation.Sam"), "Birdie")

        // A cleared score is entered again like on a round without the setting.
        app.buttons["score.clear.Alex"].tap()
        XCTAssertEqual(app.buttons["score.value.Alex"].value as? String, "Not set")
        XCTAssertFalse(element("score.notation.Alex").exists)
        XCTAssertTrue(app.buttons["scoring.parForRest"].waitForExistence(timeout: 5))
        attachScreenshot("hole-1-changed")
        app.buttons["score.plus.Alex"].tap()
        XCTAssertEqual(app.buttons["score.value.Alex"].value as? String, "4")
        XCTAssertFalse(app.buttons["scoring.parForRest"].exists)

        // Hole 2, a par 5, and hole 3, a par 3, where everybody is offered the greenie.
        app.buttons["scoring.next"].tap()
        XCTAssertEqual(label(of: "scoring.hole.title"), "Hole 2")
        XCTAssertEqual(app.buttons["score.value.Zach"].value as? String, "5")
        XCTAssertEqual(app.buttons["score.value.Jo"].value as? String, "5")
        app.buttons["score.plus.Jo"].tap()
        XCTAssertEqual(app.buttons["score.value.Jo"].value as? String, "6")
        app.buttons["scoring.next"].tap()
        XCTAssertEqual(label(of: "scoring.hole.title"), "Hole 3")
        XCTAssertEqual(app.buttons["score.value.Alex"].value as? String, "3")
        let greenieOptions = app.buttons["greenie.option.none"]
        reach(greenieOptions)
        XCTAssertTrue(app.buttons["greenie.option.Alex"].exists)
        XCTAssertTrue(app.buttons["greenie.option.Jo"].exists)
        attachScreenshot("hole-3-greenie-options")

        // The changes are on the scorecard.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(scoreRound.waitForExistence(timeout: 5))
        XCTAssertEqual(label(of: "detail.holesCompleted"), "Holes completed, 18 of 18")
        XCTAssertTrue(label(of: "scorecard.Out.Zach").hasPrefix("Zach, 5, 5, 3, 4, 4, 3, 5, 4, 4, 37"))
        XCTAssertTrue(label(of: "scorecard.Out.Sam").hasPrefix("Sam, 3, 5, 3, 4, 4, 3, 5, 4, 4, 35"))
        XCTAssertTrue(label(of: "scorecard.Out.Jo").hasPrefix("Jo, 4, 6, 3, 4, 4, 3, 5, 4, 4, 37"))
    }

    // MARK: Helpers

    /// A SwiftUI toggle is a switch with the switch itself inside; the outer
    /// one does not always react to a tap.
    private func flip(_ toggle: XCUIElement) {
        let inner = toggle.switches.firstMatch
        (inner.exists ? inner : toggle).tap()
    }

    /// Swipes the list up until the element can be tapped, clear of the strip
    /// of holes at the top and the bar at the bottom.
    private func reach(_ element: XCUIElement) {
        if !element.exists { _ = element.waitForExistence(timeout: 2) }
        let list = app.collectionViews.firstMatch
        for _ in 0..<8 {
            if isReachable(element) { return }
            let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(isReachable(element), "\(element) cannot be reached")
    }

    private func isReachable(_ element: XCUIElement) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let next = app.buttons["scoring.next"]
        guard next.exists else { return true }
        let strip = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'scoring.jump.'")).firstMatch
        return element.frame.maxY <= next.frame.minY - 8 && element.frame.minY >= strip.frame.maxY + 8
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
        attachment.name = "par-\(name)-\(scheme)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
