import Foundation
import SwiftData
import Testing
@testable import Wad

/// Paid markers on the finished round of `DebugRounds.finalPush`, through the
/// real engine bundle and an in-memory store.
///
/// As seeded: Zach +$128.00, Sam -$61.00, Alex -$67.00, so Alex pays Zach
/// $67.00 and Sam pays Zach $61.00 (worked out in RoundWalkthroughUITests).
/// Without the greenie of hole 3 (Alex +10, Zach -5, Sam -5): Zach +$133.00,
/// Sam -$56.00, Alex -$77.00, so Alex pays Zach $77.00 and Sam pays Zach $56.00.
@MainActor
struct PaymentTests {
    let container: ModelContainer
    let bridge: EngineBridge
    let round: Round
    let day = Date(timeIntervalSince1970: 1_790_424_000)

    init() throws {
        container = try ModelContainer(for: Round.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        bridge = try EngineBridge()
        round = try DebugRounds.finalPush(using: bridge, startedAt: day)
        container.mainContext.insert(round)
        try container.mainContext.save()
    }

    private var ledger: PaymentLedger { PaymentLedger(round: round) }

    private func settlement() throws -> RoundSettlement {
        try RoundSettlement(round: round, bridge: bridge)
    }

    private func status() throws -> PaymentStatus {
        PaymentStatus(settlement: try settlement(), records: round.paidRecords)
    }

    private func payment(_ number: Int) throws -> RoundSettlement.Payment {
        try #require(try settlement().payments.dropFirst(number - 1).first)
    }

    // MARK: Marking

    @Test func nothingIsPaidToStartWith() throws {
        let status = try status()
        #expect(status.isReadyForPayment)
        #expect(status.transfers.map(\.payment.amountCents) == [6700, 6100])
        #expect(status.transfers.map(\.number) == [1, 2])
        #expect(status.transfers.map(\.isPaid) == [false, false])
        #expect(status.stalePayments.isEmpty)
        #expect(status.paidCount == 0)
        #expect(!status.isAllSettled)
    }

    @Test func aMarkerRecordsWhoPaidWhomHowMuchAndWhen() throws {
        try ledger.markPaid(try payment(1), in: try settlement(), at: day)

        #expect(round.paidRecords == [PaidRecord(payerID: "alex", payeeID: "zach", amountCents: 6700, paidAt: day)])
        let status = try status()
        #expect(status.transfers.map(\.paidAt) == [day, nil])
        #expect(status.paidCount == 1)
        #expect(!status.isAllSettled)

        // It is in the store.
        let markers = try ModelContext(container).fetch(FetchDescriptor<PaidMarker>())
        #expect(markers.map(\.amountCents) == [6700])
        #expect(markers.first?.round?.id == round.id)
    }

    @Test func markingAgainKeepsTheFirstDate() throws {
        try ledger.markPaid(try payment(1), in: try settlement(), at: day)
        try ledger.markPaid(try payment(1), in: try settlement(), at: day.addingTimeInterval(3600))

        #expect(round.paidRecords.map(\.paidAt) == [day])
    }

    @Test func allSettledWhenEveryTransferIsPaid() throws {
        try ledger.markPaid(try payment(1), in: try settlement(), at: day)
        #expect(try !status().isAllSettled)
        try ledger.markPaid(try payment(2), in: try settlement(), at: day)
        #expect(try status().isAllSettled)
        #expect(try status().paidCount == 2)
    }

    @Test func markingUnpaidRemovesTheMarker() throws {
        try ledger.markPaid(try payment(1), in: try settlement(), at: day)
        try ledger.markPaid(try payment(2), in: try settlement(), at: day)
        try ledger.markUnpaid(try payment(1))

        #expect(try status().transfers.map(\.isPaid) == [false, true])
        #expect(try !status().isAllSettled)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<PaidMarker>()) == 1)

        // Marking a transfer that is not paid changes nothing.
        try ledger.markUnpaid(try payment(1))
        #expect(try status().transfers.map(\.isPaid) == [false, true])
    }

    @Test func onlyAPaymentOfTheSettlementCanBeMarked() throws {
        var other = try payment(1)
        other.amountCents = 6800
        #expect(throws: PaymentError.notATransfer) {
            try ledger.markPaid(other, in: try settlement(), at: day)
        }
        var reversed = try payment(1)
        (reversed.fromID, reversed.toID) = (reversed.toID, reversed.fromID)
        #expect(throws: PaymentError.notATransfer) {
            try ledger.markPaid(reversed, in: try settlement(), at: day)
        }
        #expect(round.paidRecords.isEmpty)
    }

    // MARK: Not final

    @Test func aProvisionalSettlementCannotBePaid() throws {
        round.setGross(nil, playerID: "sam", hole: 18)
        let settlement = try settlement()
        #expect(!settlement.isFinal)
        #expect(!settlement.isReadyForPayment)
        let first = try #require(settlement.payments.first)
        #expect(throws: PaymentError.roundIncomplete) {
            try ledger.markPaid(first, in: settlement, at: day)
        }
        #expect(round.paidRecords.isEmpty)
        #expect(try !status().isAllSettled)
    }

    @Test func aGreenieThatIsNotPaidKeepsTheSettlementFromBeingPaid() throws {
        // Alex's par on hole 3 becomes a bogey: the greenie is recorded and not paid.
        round.setGross(4, playerID: "alex", hole: 3)
        let settlement = try settlement()
        #expect(settlement.isFinal)
        #expect(settlement.unpaidGreenies.map(\.hole) == [3])
        #expect(!settlement.isReadyForPayment)
        let first = try #require(settlement.payments.first)
        #expect(throws: PaymentError.settlementHasIssues) {
            try ledger.markPaid(first, in: settlement, at: day)
        }
        #expect(round.paidRecords.isEmpty)
    }

    @Test func aPaidTransferCanBeMarkedUnpaidOnAProvisionalSettlement() throws {
        try ledger.markPaid(try payment(1), in: try settlement(), at: day)
        // Hole 18 was pushed and nobody holds the back nine's Wad, so the amounts stay.
        round.setGross(nil, playerID: "sam", hole: 18)
        let status = try status()
        #expect(!status.isReadyForPayment)
        #expect(!status.isAllSettled)
        let paid = try #require(status.transfers.first { $0.isPaid })
        #expect(paid.payment.amountCents == 6700)
        try ledger.markUnpaid(paid.payment)
        #expect(round.paidRecords.isEmpty)
    }

    // MARK: Corrections

    @Test func aCorrectionMakesTheMarkersStaleAndPaysNothingElse() throws {
        try ledger.markPaid(try payment(1), in: try settlement(), at: day)
        try ledger.markPaid(try payment(2), in: try settlement(), at: day.addingTimeInterval(60))
        #expect(try status().isAllSettled)

        // The greenie of hole 3 is taken back.
        round.hole(3)?.greenieWinnerID = nil

        let status = try status()
        #expect(status.isReadyForPayment)
        #expect(status.transfers.map(\.payment.fromName) == ["Alex", "Sam"])
        #expect(status.transfers.map(\.payment.toName) == ["Zach", "Zach"])
        #expect(status.transfers.map(\.payment.amountCents) == [7700, 5600])
        // Same payer and payee, another amount: not paid.
        #expect(status.transfers.map(\.isPaid) == [false, false])
        #expect(!status.isAllSettled)
        #expect(status.stalePayments.map(\.record) == [
            PaidRecord(payerID: "alex", payeeID: "zach", amountCents: 6700, paidAt: day),
            PaidRecord(payerID: "sam", payeeID: "zach", amountCents: 6100, paidAt: day.addingTimeInterval(60)),
        ])
        #expect(status.stalePayments.map(\.payerName) == ["Alex", "Sam"])
        #expect(status.stalePayments.map(\.payeeName) == ["Zach", "Zach"])

        let line = PaymentText.stale(try #require(status.stalePayments.first))
        #expect(line.title == "Alex paid Zach $67.00")
        #expect(line.detail?.hasPrefix("Recorded before a correction") == true)
    }

    @Test func aStaleMarkerCanBeRemoved() throws {
        try ledger.markPaid(try payment(1), in: try settlement(), at: day)
        try ledger.markPaid(try payment(2), in: try settlement(), at: day)
        round.hole(3)?.greenieWinnerID = nil

        let stale = try #require(try status().stalePayments.first)
        try ledger.removeStale(stale.record)

        #expect(try status().stalePayments.map(\.record.payerID) == ["sam"])
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<PaidMarker>()) == 1)
    }

    @Test func aMarkerCountsAgainWhenTheCorrectionIsTakenBack() throws {
        try ledger.markPaid(try payment(1), in: try settlement(), at: day)
        round.hole(3)?.greenieWinnerID = nil
        #expect(try status().transfers.map(\.isPaid) == [false, false])

        round.hole(3)?.greenieWinnerID = "alex"
        let status = try status()
        #expect(status.transfers.map(\.isPaid) == [true, false])
        #expect(status.stalePayments.isEmpty)
    }

    @Test func aNewTransferIsMarkedNextToAStaleOne() throws {
        try ledger.markPaid(try payment(1), in: try settlement(), at: day)
        round.hole(3)?.greenieWinnerID = nil
        try ledger.markPaid(try payment(1), in: try settlement(), at: day.addingTimeInterval(60))
        try ledger.markPaid(try payment(2), in: try settlement(), at: day.addingTimeInterval(60))

        let status = try status()
        #expect(status.isAllSettled)
        #expect(status.stalePayments.map(\.record.amountCents) == [6700])
    }

    @Test func theUnresolvedCarryoverIsInNoPayment() throws {
        let settlement = try settlement()
        #expect(settlement.unresolvedSkinsCarryoverCents == 2000)
        #expect(settlement.isReadyForPayment)
        // The payments are the engine's transfers, to the cent.
        let transfers = try bridge.settle(RoundStatus(round: round, bridge: bridge).gameDeltas).transfers
        #expect(settlement.payments.map(\.amountCents) == transfers.map(\.amountCents))
        #expect(settlement.payments.map(\.amountCents) == [6700, 6100])
    }

    // MARK: Deleting

    @Test func deletingTheRoundDeletesItsMarkers() throws {
        try ledger.markPaid(try payment(1), in: try settlement(), at: day)
        let context = container.mainContext
        #expect(try context.fetchCount(FetchDescriptor<PaidMarker>()) == 1)
        context.delete(round)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<PaidMarker>()) == 0)
    }

    // MARK: Venmo handles

    @Test func aHandleIsSetChangedAndCleared() throws {
        #expect(round.orderedPlayers.map(\.venmoHandle) == ["zach-golf", "sam_golfs", nil])

        try ledger.setVenmoHandle("@alex-putts", playerID: "alex")
        #expect(round.orderedPlayers.map(\.venmoHandle) == ["zach-golf", "sam_golfs", "alex-putts"])

        #expect(throws: PaymentError.invalidVenmoHandle) {
            try ledger.setVenmoHandle("al", playerID: "alex")
        }
        #expect(round.orderedPlayers.last?.venmoHandle == "alex-putts")

        try ledger.setVenmoHandle("", playerID: "alex")
        #expect(round.orderedPlayers.last?.venmoHandle == nil)

        #expect(throws: PaymentError.unknownPlayer("jo")) {
            try ledger.setVenmoHandle("jo-golfs", playerID: "jo")
        }
    }

    @Test func theWordingNamesPayerPayeeAmountAndHandle() throws {
        let payment = try payment(1)
        #expect(PaymentText.venmoDetail(.pay, payment: payment, recipient: "zach-golf")
            == "Alex pays Zach (@zach-golf) $67.00. On Alex's phone.")
        #expect(PaymentText.venmoDetail(.request, payment: payment, recipient: "alex-putts")
            == "Zach requests $67.00 from Alex (@alex-putts). On Zach's phone.")
        #expect(PaymentText.venmoDetail(.pay, payment: payment, recipient: nil) == nil)
        #expect(PaymentText.recipientID(.pay, payment: payment) == "zach")
        #expect(PaymentText.recipientID(.request, payment: payment) == "alex")
        #expect(PaymentText.missingHandle(.request, payment: payment) == "Alex has no Venmo handle.")
    }
}
