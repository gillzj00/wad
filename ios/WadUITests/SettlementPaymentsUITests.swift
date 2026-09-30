import XCTest

/// Paying and marking paid on the settlement screen, and the round history.
///
/// The round is the finished one of `-debugSeedRound finalPush`, started on
/// 2026-09-26 at 12:00 UTC: Alex pays Zach $67.00 and Sam pays Zach $61.00,
/// and $20.00 of skins is unresolved and in neither (the amounts are checked
/// by RoundSettlementTests). Zach (@zach-golf) and Sam (@sam_golfs) have a
/// Venmo handle, Alex has none.
///
/// Venmo is never opened: with `-debugLinkOpener` the app records the link it
/// would open and shows it, and the test checks that link.
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
            if element.exists, element.isHittable { return }
            let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(element.exists && element.isHittable, "\(element) cannot be reached")
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
