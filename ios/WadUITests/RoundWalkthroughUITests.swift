import XCTest

/// Sets up a round, scores it and settles it the way a user does, by tapping
/// and typing, on an empty in-memory store. Attaches a screenshot of each screen.
@MainActor
final class RoundWalkthroughUITests: XCTestCase {
    private let app = XCUIApplication()
    private let courseName = "Walkthrough Links"
    private let players = [("Zach", "15"), ("Sam", "7"), ("Alex", "7")]
    /// Off while a test repeats screens another test already attaches.
    private var attachesScreenshots = true

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

    /// Scores all 18 holes and checks the settlement against amounts worked out by hand.
    ///
    /// Every hole is a par 4 except the third (par 3); Zach (15) gets a tick on
    /// holes 1 to 8 against Sam and Alex (7). Skins $5, Wad $7 and $2, greenies
    /// $5. Pars except where listed; a winner collects from the two others.
    ///
    /// Skins (amount from each other player):
    ///  1  Zach 5 (net 4), 4, 4           push, $5 carries
    ///  2  nets 3 4 4                     Zach wins $10
    ///  3  par 3: Zach 3 (net 2), Alex 4  Zach wins $5
    ///  4  nets 3 4 4                     Zach wins $5
    ///  5  Sam 3, Zach net 3              push, $5 carries
    ///  6  nets 3 4 4                     Zach wins $10
    ///  7  Alex 3, Zach net 3             push, $5 carries
    ///  8  Zach 5 (net 4)                 push, $10 carries
    ///  9  Alex 3                         Alex wins $15
    /// 10  Sam 3                          Sam wins $5
    /// 11, 12  all 4                      push, push, $10 carries
    /// 13  Zach 3                         Zach wins $15
    /// 14, 15  all 4                      push, push, $10 carries
    /// 16  Sam 3                          Sam wins $15
    /// 17  all 4                          push, $5 carries
    /// 18  Alex 3                         Alex wins $10
    ///  Zach won 10 + 5 + 5 + 10 + 15 = 45; Sam 5 + 15 = 20; Alex 15 + 10 = 25.
    ///  Zach 2 x 45 - (20 + 25) = +45; Sam 2 x 20 - (45 + 25) = -30;
    ///  Alex 2 x 25 - (45 + 20) = -15
    /// Wad, front: hole 1 Sam ($7) then Zach ($9), hole 3 Alex ($11), hole 7 Sam
    ///  ($13): Sam +26, Zach -13, Alex -13. Back: hole 15 Alex ($7): Alex +14,
    ///  Zach -7, Sam -7. Wad: Zach -20, Sam +19, Alex +1
    /// Greenies: hole 3 Sam: Sam +10, Zach -5, Alex -5
    /// Net: Zach 45 - 20 - 5 = +20; Sam -30 + 19 + 10 = -1; Alex -15 + 1 - 5 = -19
    /// Payments: Alex pays Zach $19.00, Sam pays Zach $1.00.
    func testScoresAFullRoundAndSettles() throws {
        continueAfterFailure = false
        app.launchArguments = ["-inMemoryStore"]
        app.launch()

        // The setup screens are attached by the test above.
        attachesScreenshots = false
        let newRound = app.buttons["New round"].firstMatch
        XCTAssertTrue(newRound.waitForExistence(timeout: 10))
        newRound.tap()
        setUpCourse()
        setUpPlayers()
        XCTAssertTrue(app.navigationBars["Games"].waitForExistence(timeout: 5))
        app.buttons["Create"].tap()
        attachesScreenshots = true

        // The settlement of a round without scores is provisional.
        let settlementLink = element("detail.settlement")
        XCTAssertTrue(settlementLink.waitForExistence(timeout: 5))
        settlementLink.tap()
        XCTAssertTrue(app.navigationBars["Settlement"].waitForExistence(timeout: 5))
        XCTAssertTrue(label(of: "settlement.status").hasPrefix("Provisional, no holes scored"))
        XCTAssertEqual(label(of: "settlement.noPayments"), "Nobody owes anything so far")
        attachScreenshot("14-settlement-no-scores")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let scoreRound = element("detail.scoreRound")
        XCTAssertTrue(scoreRound.waitForExistence(timeout: 5))
        scoreRound.tap()
        XCTAssertTrue(element("scoring.hole.title").waitForExistence(timeout: 5))

        score(1, gross: ["Zach": 5, "Sam": 4, "Alex": 4], wadMakers: ["Sam", "Zach"])
        score(2)
        score(3, par: 3, gross: ["Zach": 3, "Sam": 3, "Alex": 4], wadMakers: ["Alex"], greenie: "Sam")
        score(4)
        score(5, gross: ["Sam": 3])
        score(6)
        score(7, gross: ["Alex": 3], wadMakers: ["Sam"])
        score(8, gross: ["Zach": 5])
        score(9, gross: ["Alex": 3], staysOnHole: true)
        XCTAssertTrue(label(of: "status.wad").hasPrefix("Sam holds the Wad at $13.00"))
        // A settlement is offered on the last hole only.
        XCTAssertFalse(element("scoring.settlement").exists)
        attachScreenshot("15-hole-9-scored")
        app.buttons["scoring.next"].tap()

        score(10, gross: ["Sam": 3])
        score(11)
        score(12)
        score(13, gross: ["Zach": 3])
        score(14)
        score(15, wadMakers: ["Alex"])
        score(16, gross: ["Sam": 3])
        score(17)
        score(18, gross: ["Alex": 3], staysOnHole: true)

        // Hole 18: the round is complete and the settlement is offered.
        XCTAssertFalse(app.buttons["scoring.next"].isEnabled)
        XCTAssertTrue(label(of: "status.wad").hasPrefix("Alex holds the Wad at $7.00"))
        let settle = element("scoring.settlement")
        reach(settle)
        attachScreenshot("16-hole-18-scored")
        settle.tap()

        // Who pays whom.
        XCTAssertTrue(app.navigationBars["Settlement"].waitForExistence(timeout: 5))
        XCTAssertTrue(label(of: "settlement.status").hasPrefix("Final"))
        XCTAssertEqual(label(of: "settlement.payment.1"), "Alex pays Zach $19.00")
        XCTAssertEqual(label(of: "settlement.payment.2"), "Sam pays Zach $1.00")
        XCTAssertFalse(element("settlement.payment.3").exists)
        XCTAssertFalse(element("settlement.carryover").exists)
        XCTAssertEqual(label(of: "settlement.position.Zach"), "Zach: Won $20.00")
        XCTAssertEqual(label(of: "settlement.position.Sam"), "Sam: Owes $1.00")
        XCTAssertEqual(label(of: "settlement.position.Alex"), "Alex: Owes $19.00")
        attachScreenshot("17-settlement-payments")

        // Per game.
        reach(element("settlement.skins.2"))
        XCTAssertEqual(label(of: "settlement.games.Zach"), "Zach: Skins +$45.00, Wad -$20.00, Greenies -$5.00")
        XCTAssertEqual(label(of: "settlement.games.Sam"), "Sam: Skins -$30.00, Wad +$19.00, Greenies +$10.00")
        XCTAssertEqual(label(of: "settlement.games.Alex"), "Alex: Skins -$15.00, Wad +$1.00, Greenies -$5.00")
        attachScreenshot("18-settlement-by-game")

        // The games, hole by hole.
        XCTAssertTrue(label(of: "settlement.skins.2").hasPrefix("Hole 2: Zach wins $10.00 from each other player"))
        reach(element("settlement.skins.9"))
        XCTAssertTrue(label(of: "settlement.skins.8").hasPrefix("Hole 8: Pushed"))
        XCTAssertTrue(label(of: "settlement.skins.9").hasPrefix("Hole 9: Alex wins $15.00 from each other player"))
        attachScreenshot("19-settlement-skins")
        reach(element("settlement.skins.18"))
        XCTAssertTrue(label(of: "settlement.skins.18").hasPrefix("Hole 18: Alex wins $10.00 from each other player"))
        reach(element("settlement.wad.front.make.4"))
        XCTAssertTrue(label(of: "settlement.wad.front").hasPrefix("Sam holds the Wad at $13.00"))
        XCTAssertEqual(label(of: "settlement.wad.front.make.1"), "Hole 1: Sam holds at $7.00")
        XCTAssertEqual(label(of: "settlement.wad.front.make.4"), "Hole 7: Sam holds at $13.00")
        reach(element("settlement.greenie.3"))
        XCTAssertTrue(label(of: "settlement.wad.back").hasPrefix("Alex holds the Wad at $7.00"))
        XCTAssertTrue(label(of: "settlement.greenie.3").hasPrefix("Hole 3: Sam wins the greenie"))
        attachScreenshot("20-settlement-wad-greenies")

        // The round reaches the same settlement.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element("scoring.hole.title").waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element("detail.settlement").waitForExistence(timeout: 5))
        XCTAssertEqual(label(of: "detail.holesCompleted"), "Holes completed, 18 of 18")
        attachScreenshot("21-round-detail-finished")
        element("detail.settlement").tap()
        XCTAssertEqual(label(of: "settlement.payment.1"), "Alex pays Zach $19.00")
    }

    /// A finished round seeded by `-debugSeedRound finalPush` (DebugRounds.finalPush):
    /// pars everywhere, so Zach wins the holes he has a tick on (1, 4, 5, 8, 10,
    /// 12 and 14, stroke indexes 7, 3, 1, 5, 8, 2 and 6) and the other holes
    /// push; his bogey on 17 (stroke index 4) nets 4 and pushes too, so holes 15
    /// to 18 leave 4 x $5 = $20.00 unresolved.
    ///  Skins from each: hole 1 $5, 4 $15, 5 $5, 8 $15, 10 $10, 12 $10, 14 $10 = $70
    ///   Zach +140, Sam -70, Alex -70
    ///  Wad, front: Sam holds at $7: Sam +14, Zach -7, Alex -7. Back: nobody.
    ///  Greenies: hole 3 Alex: Alex +10, Zach -5, Sam -5
    ///  Net: Zach 140 - 7 - 5 = +128; Sam -70 + 14 - 5 = -61; Alex -70 - 7 + 10 = -67
    ///  Payments: Alex pays Zach $67.00, Sam pays Zach $61.00. The $20.00 is in none.
    func testShowsAnUnresolvedCarryoverAndAGreenieThatIsNotPaid() throws {
        continueAfterFailure = false
        app.launchArguments = ["-inMemoryStore", "-debugSeedRound", "finalPush"]
        app.launch()

        let settlementLink = element("detail.settlement")
        XCTAssertTrue(settlementLink.waitForExistence(timeout: 10))
        XCTAssertEqual(label(of: "detail.holesCompleted"), "Holes completed, 18 of 18")
        settlementLink.tap()

        XCTAssertTrue(label(of: "settlement.status").hasPrefix("Final"))
        let carryover = label(of: "settlement.carryover")
        XCTAssertTrue(carryover.hasPrefix("$20.00 skins carryover is unresolved"))
        XCTAssertTrue(carryover.contains("NOT paid out"))
        XCTAssertTrue(carryover.contains("awaiting a rules decision"))
        XCTAssertEqual(label(of: "settlement.payment.1"), "Alex pays Zach $67.00")
        XCTAssertEqual(label(of: "settlement.payment.2"), "Sam pays Zach $61.00")
        XCTAssertFalse(element("settlement.payment.3").exists)
        XCTAssertEqual(label(of: "settlement.position.Zach"), "Zach: Won $128.00")
        attachScreenshot("30-carryover-settlement")

        reach(element("settlement.skins.2"))
        XCTAssertEqual(label(of: "settlement.games.Zach"), "Zach: Skins +$140.00, Wad -$7.00, Greenies -$5.00")
        XCTAssertEqual(label(of: "settlement.games.Sam"), "Sam: Skins -$70.00, Wad +$14.00, Greenies -$5.00")
        XCTAssertEqual(label(of: "settlement.games.Alex"), "Alex: Skins -$70.00, Wad -$7.00, Greenies +$10.00")
        attachScreenshot("31-carryover-by-game")
        reach(element("settlement.skins.18"))
        XCTAssertTrue(label(of: "settlement.skins.18").contains("Last hole: $20.00 is unresolved and is not paid out."))
        attachScreenshot("32-carryover-skins")

        // Alex's par on hole 3 is corrected to a bogey: the greenie is not paid.
        //  Net: Zach 140 - 7 = +133; Sam -70 + 14 = -56; Alex -70 - 7 = -77
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let scoreRound = element("detail.scoreRound")
        reach(scoreRound)
        scoreRound.tap()
        XCTAssertEqual(label(of: "scoring.hole.title"), "Hole 18")
        for _ in 0..<15 { app.buttons["scoring.previous"].tap() }
        XCTAssertEqual(label(of: "scoring.hole.title"), "Hole 3")
        let plus = app.buttons["score.plus.Alex"]
        reach(plus)
        plus.tap()
        XCTAssertEqual(app.buttons["score.value.Alex"].value as? String, "4")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        XCTAssertTrue(element("detail.settlement").waitForExistence(timeout: 5))
        element("detail.settlement").tap()
        let fix = element("settlement.fix.greenie.3")
        XCTAssertTrue(fix.waitForExistence(timeout: 5))
        XCTAssertTrue(fix.label.contains("Hole 3 greenie is not paid"))
        XCTAssertEqual(label(of: "settlement.payment.1"), "Alex pays Zach $77.00")
        XCTAssertEqual(label(of: "settlement.payment.2"), "Sam pays Zach $56.00")
        attachScreenshot("33-settlement-greenie-not-paid")

        // The link opens the hole, where the greenie is cleared.
        fix.tap()
        XCTAssertEqual(label(of: "scoring.hole.title"), "Hole 3")
        let clear = app.buttons["greenie.clear"]
        reach(clear)
        attachScreenshot("34-hole-3-greenie-to-fix")
        clear.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(label(of: "settlement.status").hasPrefix("Final"))
        XCTAssertFalse(element("settlement.fix.greenie.3").exists)
        XCTAssertEqual(label(of: "settlement.payment.1"), "Alex pays Zach $77.00")
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

        let strokeIndexes = app.buttons["setup.strokeIndexes"]
        scrollTo(strokeIndexes, direction: .down)
        strokeIndexes.tap()
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

    /// Scores the hole on screen: the gross scores listed, par for the other
    /// players, the Wad makers in order and the greenie winner. Then moves to
    /// the next hole, unless it stays.
    private func score(
        _ hole: Int,
        par: Int = 4,
        gross: [String: Int] = [:],
        wadMakers: [String] = [],
        greenie: String? = nil,
        staysOnHole: Bool = false
    ) {
        XCTAssertEqual(label(of: "scoring.hole.title"), "Hole \(hole)")
        for (name, _) in players {
            guard let target = gross[name] else { continue }
            // The first tap gives par.
            let plus = app.buttons["score.plus.\(name)"]
            reach(plus)
            plus.tap()
            let step = app.buttons[target > par ? "score.plus.\(name)" : "score.minus.\(name)"]
            for _ in 0..<abs(target - par) { step.tap() }
            XCTAssertEqual(app.buttons["score.value.\(name)"].value as? String, String(target))
        }
        if gross.count < players.count {
            let parForRest = app.buttons["scoring.parForRest"]
            reach(parForRest)
            parForRest.tap()
        }
        for maker in wadMakers {
            let chip = app.buttons["wad.maker.\(maker)"]
            reach(chip)
            chip.tap()
        }
        if let greenie {
            let chip = app.buttons["greenie.option.\(greenie)"]
            reach(chip)
            chip.tap()
        }
        if !staysOnHole {
            app.buttons["scoring.next"].tap()
        }
    }

    // MARK: Helpers

    private enum Direction { case up, down }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func label(of identifier: String) -> String {
        let element = element(identifier)
        XCTAssertTrue(element.exists || element.waitForExistence(timeout: 5), "\(identifier) not found")
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
        // Rows appear a moment after a screen or the keyboard changes; only scroll for rows that are off screen.
        if !element.exists { _ = element.waitForExistence(timeout: 2) }
        for _ in 0..<8 {
            if isReachable(element) { break }
            let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: direction == .up ? 0.6 : 0.4))
            let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: direction == .up ? 0.3 : 0.7))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(isReachable(element), "\(element) cannot be reached")
    }

    /// Scrolls towards the element, whichever side of the screen it is off.
    private func reach(_ element: XCUIElement) {
        if isReachable(element) { return }
        _ = element.waitForExistence(timeout: 2)
        let list = app.collectionViews.firstMatch
        let isAbove = element.exists && element.frame.midY < list.frame.midY
        scrollTo(element, direction: isAbove ? .down : .up)
    }

    /// On screen, and not under the scoring screen's bottom bar or its strip of
    /// holes at the top.
    private func isReachable(_ element: XCUIElement) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let next = app.buttons["scoring.next"]
        guard next.exists else { return true }
        let strip = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'scoring.jump.'")).firstMatch
        return element.frame.maxY <= next.frame.minY - 8 && element.frame.minY >= strip.frame.maxY + 8
    }

    private func attachScreenshot(_ name: String) {
        guard attachesScreenshots else { return }
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
