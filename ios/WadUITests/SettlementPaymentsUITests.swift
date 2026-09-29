import XCTest

/// Paying and marking paid on the settlement screen, and the round history.
///
/// The round is the finished one of `-debugSeedRound finalPush`, started on
/// 2026-09-26 at 12:00 UTC: Alex pays Zach $67.00 and Sam pays Zach $61.00,
/// and $20.00 of skins is unresolved and in neither (worked out in
/// RoundWalkthroughUITests). Zach (@zach-golf) and Sam (@sam_golfs) have a
/// Venmo handle, Alex has none.
///
/// Venmo is never opened: with `-debugLinkOpener` the app records the link it
/// would open and shows it, and the tests check that link.
@MainActor
final class SettlementPaymentsUITests: XCTestCase {
    private let app = XCUIApplication()
    private let seed = ["-inMemoryStore", "-debugSeedRound", "finalPush", "-debugSeedStartedAt", "1790424000"]
    private let note = "Wad%3A%20Carryover%20Links%20Sep%2026"

    override func setUp() {
        continueAfterFailure = false
    }

    func testPaysWithVenmoMarksPaidAndShowsTheHistory() throws {
        app.launchArguments = seed + ["-debugLinkOpener", "opens"]
        app.launch()
        openSettlement()

        // A final settlement: both payments can be paid, none is.
        XCTAssertTrue(label(of: "settlement.status").hasPrefix("Final"))
        let first = element("settlement.payment.1")
        let second = element("settlement.payment.2")
        XCTAssertEqual(first.label, "Alex pays Zach $67.00")
        XCTAssertEqual(first.value as? String, "Not paid")
        XCTAssertEqual(second.label, "Sam pays Zach $61.00")
        XCTAssertEqual(second.value as? String, "Not paid")
        XCTAssertFalse(element("settlement.allSettled").exists)
        XCTAssertFalse(element("settlement.stale.1").exists)
        XCTAssertTrue(label(of: "settlement.carryover").hasPrefix("$20.00 skins carryover is unresolved"))
        attachScreenshot("60-settlement-payment-actions")

        // The payment: pay goes to Zach's handle; a request would go to Alex, who has none.
        first.tap()
        XCTAssertEqual(label(of: "payment.summary"), "Alex pays Zach $67.00")
        XCTAssertEqual(label(of: "payment.state"), "Not paid")
        let pay = element("payment.venmo.pay")
        let request = element("payment.venmo.request")
        XCTAssertEqual(pay.label, "Pay with Venmo")
        XCTAssertEqual(pay.value as? String, "Alex pays Zach (@zach-golf) $67.00. On Alex's phone.")
        XCTAssertTrue(pay.isEnabled)
        XCTAssertEqual(request.label, "Request with Venmo")
        XCTAssertEqual(request.value as? String, "Alex has no Venmo handle.")
        XCTAssertFalse(request.isEnabled)
        XCTAssertEqual(label(of: "debug.openedLink"), "None")
        attachScreenshot("61-payment-sheet")

        // Pay with Venmo: the link, and nothing is paid without the group saying so.
        pay.tap()
        let confirm = app.alerts["Was the payment made?"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        attachScreenshot("62-payment-confirm")
        confirm.buttons["Not yet"].tap()
        XCTAssertEqual(
            label(of: "debug.openedLink"),
            "venmo://paycharge?txn=pay&recipients=zach-golf&amount=67.00&note=\(note)"
        )
        XCTAssertEqual(label(of: "payment.state"), "Not paid")

        // Alex gets a handle. One that is too short is not saved.
        element("payment.addHandle.Alex").tap()
        let field = app.textFields["venmoHandle.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("@al")
        XCTAssertTrue(element("venmoHandle.invalid").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["venmoHandle.save"].isEnabled)
        field.typeText("ex-putts")
        XCTAssertTrue(waitUntil { self.app.buttons["venmoHandle.save"].isEnabled })
        app.buttons["venmoHandle.save"].tap()
        XCTAssertTrue(waitUntil { request.exists && request.isEnabled })
        XCTAssertEqual(request.value as? String, "Zach requests $67.00 from Alex (@alex-putts). On Zach's phone.")
        XCTAssertFalse(element("payment.addHandle.Alex").exists)

        // Request with Venmo is a charge to the payer. This time it was paid.
        request.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.buttons["Mark as paid"].tap()
        XCTAssertEqual(
            label(of: "debug.openedLink"),
            "venmo://paycharge?txn=charge&recipients=alex-putts&amount=67.00&note=\(note)"
        )
        XCTAssertTrue(waitUntil { self.label(of: "payment.state").hasPrefix("Paid ") })
        XCTAssertFalse(pay.exists)
        XCTAssertFalse(element("payment.markPaid").exists)
        attachScreenshot("63-payment-paid")

        // Not paid after all, then paid by hand.
        tapWhenThere("payment.markUnpaid")
        XCTAssertTrue(waitUntil { self.label(of: "payment.state") == "Not paid" })
        XCTAssertTrue(pay.exists)
        tapWhenThere("payment.markPaid")
        XCTAssertTrue(waitUntil { self.label(of: "payment.state").hasPrefix("Paid ") })
        app.buttons["payment.done"].tap()

        XCTAssertTrue(waitUntil { first.value as? String == "Paid" })
        XCTAssertEqual(second.value as? String, "Not paid")
        XCTAssertFalse(element("settlement.allSettled").exists)
        attachScreenshot("64-settlement-one-paid")

        // The second payment: all settled.
        second.tap()
        tapWhenThere("payment.markPaid")
        XCTAssertTrue(waitUntil { self.label(of: "payment.state").hasPrefix("Paid ") })
        app.buttons["payment.done"].tap()
        XCTAssertTrue(element("settlement.allSettled").waitForExistence(timeout: 5))
        XCTAssertEqual(label(of: "settlement.allSettled"), "All settled")
        XCTAssertEqual(second.value as? String, "Paid")
        // The amounts are the same, and the carryover is still not paid.
        XCTAssertEqual(first.label, "Alex pays Zach $67.00")
        XCTAssertEqual(second.label, "Sam pays Zach $61.00")
        XCTAssertTrue(label(of: "settlement.carryover").contains("NOT paid out"))
        attachScreenshot("65-settlement-all-settled")

        // The history.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element("detail.settlement").waitForExistence(timeout: 5))
        reach(element("detail.venmoHandle.Alex"))
        XCTAssertTrue(element("detail.venmoHandle.Alex").label.contains("@alex-putts"))
        XCTAssertTrue(element("detail.venmoHandle.Zach").label.contains("@zach-golf"))
        attachScreenshot("66-detail-venmo-handles")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element("rounds.row.Carryover Links").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Carryover Links"].exists)
        XCTAssertTrue(app.staticTexts["Sat, Sep 26, 2026"].exists)
        XCTAssertTrue(app.staticTexts["Zach, Sam, Alex"].exists)
        XCTAssertTrue(app.staticTexts["Final: Zach won $128.00"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["All settled"].exists)
        attachScreenshot("67-history")
    }

    func testFallsBackWithoutVenmoAndKeepsAPaymentRecordedBeforeACorrection() throws {
        app.launchArguments = seed + ["-debugLinkOpener", "fails"]
        app.launch()
        openSettlement()

        // Venmo is not installed: the website is offered, and marking by hand.
        let second = element("settlement.payment.2")
        XCTAssertEqual(second.label, "Sam pays Zach $61.00")
        second.tap()
        tapWhenThere("payment.venmo.pay")
        let failed = app.alerts["Venmo could not be opened"]
        XCTAssertTrue(failed.waitForExistence(timeout: 5))
        XCTAssertTrue(failed.buttons["Mark as paid by hand"].exists)
        attachScreenshot("70-venmo-not-installed")
        failed.buttons["Open venmo.com"].tap()
        let confirm = app.alerts["Was the payment made?"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.buttons["Mark as paid"].tap()
        XCTAssertEqual(
            label(of: "debug.openedLink"),
            "https://venmo.com/zach-golf?txn=pay&amount=61.00&note=\(note)"
        )
        XCTAssertTrue(waitUntil { self.label(of: "payment.state").hasPrefix("Paid ") })
        app.buttons["payment.done"].tap()
        XCTAssertTrue(waitUntil { second.value as? String == "Paid" })

        // The history: final, one of two paid.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element("detail.scoreRound").waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Final: Zach won $128.00"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Not settled: 1 of 2 payments paid"].exists)
        attachScreenshot("71-history-partly-paid")

        // A correction: Sam made a Wad putt on hole 18 and holds the back nine's
        // Wad at $7: Sam +14, Zach -7, Alex -7.
        //  Net: Zach 128 - 7 = +121; Sam -61 + 14 = -47; Alex -67 - 7 = -74
        element("rounds.row.Carryover Links").tap()
        tapWhenThere("detail.scoreRound")
        XCTAssertEqual(label(of: "scoring.hole.title"), "Hole 18")
        let maker = app.buttons["wad.maker.Sam"]
        reach(maker)
        maker.tap()
        XCTAssertEqual(maker.value as? String, "Make 1")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        tapWhenThere("detail.settlement")

        // The payment marked paid is kept as recorded and pays nothing.
        let first = element("settlement.payment.1")
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertEqual(first.label, "Alex pays Zach $74.00")
        XCTAssertEqual(first.value as? String, "Not paid")
        XCTAssertEqual(second.label, "Sam pays Zach $47.00")
        XCTAssertEqual(second.value as? String, "Not paid")
        let stale = element("settlement.stale.1")
        reach(stale)
        XCTAssertTrue(stale.label.hasPrefix("Sam paid Zach $61.00"))
        XCTAssertTrue(stale.label.contains("Recorded before a correction"))
        XCTAssertFalse(element("settlement.stale.2").exists)
        attachScreenshot("72-settlement-stale-payment")

        let remove = element("settlement.stale.1.remove")
        reach(remove)
        remove.tap()
        XCTAssertTrue(stale.waitForNonExistence(timeout: 5))
        XCTAssertEqual(second.value as? String, "Not paid")

        // A score is cleared: the settlement is provisional and nothing can be paid.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        tapWhenThere("detail.scoreRound")
        let clear = app.buttons["score.clear.Sam"]
        reach(clear)
        clear.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(waitUntil { self.label(of: "detail.holesCompleted") == "Holes completed, 17 of 18" })
        tapWhenThere("detail.settlement")
        XCTAssertTrue(label(of: "settlement.status").hasPrefix("Provisional"))
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertNotEqual(first.value as? String, "Not paid")
        XCTAssertNotEqual(first.value as? String, "Paid")
        if first.isHittable { first.tap() }
        XCTAssertFalse(element("payment.summary").waitForExistence(timeout: 2))
        XCTAssertFalse(element("settlement.allSettled").exists)
        attachScreenshot("73-settlement-provisional-no-actions")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element("detail.scoreRound").waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["In progress, through 17 holes"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Final: Zach won $128.00"].exists)
        attachScreenshot("74-history-in-progress")
    }

    // MARK: Helpers

    private func openSettlement() {
        let settlement = element("detail.settlement")
        XCTAssertTrue(settlement.waitForExistence(timeout: 10))
        settlement.tap()
        XCTAssertTrue(app.navigationBars["Settlement"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("settlement.payment.1").waitForExistence(timeout: 5))
    }

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

    /// Swipes the list up until the element can be tapped.
    private func reach(_ element: XCUIElement) {
        // Rows appear a moment after a screen changes; only scroll for rows that are off screen.
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

    /// On screen, and not under the scoring screen's bottom bar.
    private func isReachable(_ element: XCUIElement) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let next = app.buttons["scoring.next"]
        return !next.exists || element.frame.maxY <= next.frame.minY - 8
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
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
