import Foundation
import SwiftData
import Testing
@testable import Wad

/// The rows of the round history. The finished round is the one of
/// `DebugRounds.finalPush`: Zach +$128.00, Alex pays Zach $67.00 and Sam pays
/// Zach $61.00.
@MainActor
struct RoundSummaryTests {
    let container: ModelContainer
    let bridge: EngineBridge
    let day = Date(timeIntervalSince1970: 1_790_424_000)

    init() throws {
        container = try ModelContainer(for: Round.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        bridge = try EngineBridge()
    }

    private func finishedRound() throws -> Round {
        let round = try DebugRounds.finalPush(using: bridge, startedAt: day)
        container.mainContext.insert(round)
        return round
    }

    private func newRound() throws -> Round {
        let round = try RoundFixtures.threePlayerDraft().makeRound(using: bridge, startedAt: day)
        container.mainContext.insert(round)
        return round
    }

    private func summary(_ round: Round) throws -> RoundSummary {
        let settlement = try RoundSettlement(round: round, bridge: bridge)
        return RoundSummary(
            settlement: settlement,
            payments: PaymentStatus(settlement: settlement, records: round.paidRecords)
        )
    }

    private func scorePars(_ round: Round, holes: [Int]) {
        for hole in holes {
            for player in round.players {
                round.setGross(round.hole(hole)?.par, playerID: player.playerID, hole: hole)
            }
        }
    }

    // MARK: Summaries

    @Test func aRoundWithoutScoresIsNotStarted() throws {
        let summary = try summary(try newRound())
        #expect(summary.progress == .notStarted)
        #expect(summary.progressText == "Not started")
        #expect(summary.headline == nil)
        #expect(summary.settled == nil)
        #expect(summary.settledText == nil)
    }

    @Test func aRoundInProgressSaysHowFarItIs() throws {
        let round = try newRound()
        scorePars(round, holes: [1])
        #expect(try summary(round).progressText == "In progress, through 1 hole")

        scorePars(round, holes: Array(2...7))
        let summary = try summary(round)
        #expect(summary.progress == .inProgress(completed: 7, total: 18, inOrder: true))
        #expect(summary.progressText == "In progress, through 7 holes")
        // No result and nothing to settle before the round is final.
        #expect(summary.headline == nil)
        #expect(summary.settledText == nil)

        // A hole that only some players have scored does not count.
        round.setGross(4, playerID: "zach", hole: 8)
        #expect(try self.summary(round).progressText == "In progress, through 7 holes")

        scorePars(round, holes: [10])
        #expect(try self.summary(round).progressText == "In progress, 8 of 18 holes scored")
    }

    @Test func aFinalRoundThatIsNotSettled() throws {
        let round = try finishedRound()
        let summary = try summary(round)
        #expect(summary.progress == .final)
        #expect(summary.headline == "Zach won $128.00")
        #expect(summary.progressText == "Final: Zach won $128.00")
        #expect(summary.settled == .unsettled(paid: 0, total: 2))
        #expect(summary.settledText == "Not settled: 2 payments to make")
    }

    @Test func aFinalRoundThatIsPartlyPaid() throws {
        let round = try finishedRound()
        let settlement = try RoundSettlement(round: round, bridge: bridge)
        try PaymentLedger(round: round).markPaid(try #require(settlement.payments.first), in: settlement, at: day)

        let summary = try summary(round)
        #expect(summary.settled == .unsettled(paid: 1, total: 2))
        #expect(summary.settledText == "Not settled: 1 of 2 payments paid")
    }

    @Test func aFinalRoundThatIsSettled() throws {
        let round = try finishedRound()
        let settlement = try RoundSettlement(round: round, bridge: bridge)
        for payment in settlement.payments {
            try PaymentLedger(round: round).markPaid(payment, in: settlement, at: day)
        }

        let summary = try summary(round)
        #expect(summary.progressText == "Final: Zach won $128.00")
        #expect(summary.settled == .allSettled)
        #expect(summary.settledText == "All settled")

        // After a correction the payments marked are stale: not settled any more.
        round.hole(3)?.greenieWinnerID = nil
        let corrected = try self.summary(round)
        #expect(corrected.progressText == "Final: Zach won $133.00")
        #expect(corrected.settled == .unsettled(paid: 0, total: 2))
    }

    @Test func aFinalRoundWithAGreenieToFix() throws {
        let round = try finishedRound()
        round.setGross(4, playerID: "alex", hole: 3)
        let summary = try summary(round)
        #expect(summary.progress == .final)
        #expect(summary.settled == .needsFixing)
        #expect(summary.settledText == "Not settled: a greenie needs fixing")
    }

    @Test func aFinalRoundWhereNobodyOwesAnything() throws {
        // Sam and Alex have the same handicap and make the same scores; nothing else is recorded.
        var draft = RoundFixtures.unratedDraft()
        draft.players = [
            RoundDraft.Player(id: "sam", name: "Sam", courseHandicapText: "7"),
            RoundDraft.Player(id: "alex", name: "Alex", courseHandicapText: "7"),
        ]
        let round = try draft.makeRound(using: bridge, startedAt: day)
        container.mainContext.insert(round)
        scorePars(round, holes: Array(1...18))

        let summary = try summary(round)
        #expect(summary.progressText == "Final: All even")
        #expect(summary.settled == .nothingOwed)
        #expect(summary.settledText == "Nobody owes anything")
    }

    @Test func playersWithTheSameBestResultShareTheHeadline() throws {
        // Three players with the same handicap make par everywhere, so every
        // skin pushes. Sam wins the greenie on hole 3 and Alex the one on hole 6:
        // each collects $5 from the two others and pays $5 to the other winner.
        //  Sam +10 - 5 = +5; Alex +5; Zach -10
        var draft = RoundFixtures.threePlayerDraft()
        draft.players[0].courseHandicapText = "7"
        let round = try draft.makeRound(using: bridge, startedAt: day)
        container.mainContext.insert(round)
        scorePars(round, holes: Array(1...18))
        round.hole(3)?.greenieWinnerID = "sam"
        round.hole(6)?.greenieWinnerID = "alex"

        let summary = try summary(round)
        #expect(summary.headline == "Sam and Alex won $5.00")
        #expect(summary.settled == .unsettled(paid: 0, total: 2))
    }

    // MARK: Cache

    @Test func theEnginesRunOncePerChangeOfARound() throws {
        let cache = RoundSummaryCache()
        let round = try finishedRound()

        var key = RoundSummaryKey(round: round)
        #expect(cache.summary(for: round, key: key) == nil)
        cache.refresh(round, key: key, bridge: bridge)
        #expect(cache.computations == 1)
        #expect(cache.summary(for: round, key: key)?.progressText == "Final: Zach won $128.00")

        // Rendering again does not compute again.
        for _ in 0..<5 {
            cache.refresh(round, key: RoundSummaryKey(round: round), bridge: bridge)
        }
        #expect(cache.computations == 1)

        // A score changes: the summary in the cache is no longer the round's.
        round.hole(3)?.greenieWinnerID = nil
        key = RoundSummaryKey(round: round)
        #expect(cache.summary(for: round, key: key) == nil)
        #expect(cache.lastSummary(for: round)?.progressText == "Final: Zach won $128.00")
        cache.refresh(round, key: key, bridge: bridge)
        #expect(cache.computations == 2)
        #expect(cache.summary(for: round, key: key)?.progressText == "Final: Zach won $133.00")

        // Marking a payment paid changes it too.
        let settlement = try RoundSettlement(round: round, bridge: bridge)
        for payment in settlement.payments {
            try PaymentLedger(round: round).markPaid(payment, in: settlement, at: day)
        }
        key = RoundSummaryKey(round: round)
        #expect(cache.summary(for: round, key: key) == nil)
        cache.refresh(round, key: key, bridge: bridge)
        #expect(cache.computations == 3)
        #expect(cache.summary(for: round, key: key)?.settledText == "All settled")
    }

    @Test func roundsAreCachedSeparately() throws {
        let cache = RoundSummaryCache()
        let finished = try finishedRound()
        let new = try newRound()
        cache.refresh(finished, key: RoundSummaryKey(round: finished), bridge: bridge)
        cache.refresh(new, key: RoundSummaryKey(round: new), bridge: bridge)
        cache.refresh(finished, key: RoundSummaryKey(round: finished), bridge: bridge)

        #expect(cache.computations == 2)
        #expect(cache.summary(for: finished, key: RoundSummaryKey(round: finished))?.progress == .final)
        #expect(cache.summary(for: new, key: RoundSummaryKey(round: new))?.progress == .notStarted)

        cache.remove(finished.id)
        #expect(cache.lastSummary(for: finished) == nil)
        #expect(cache.lastSummary(for: new) != nil)
    }

    @Test func withoutTheEnginesThereIsNoSummary() throws {
        let cache = RoundSummaryCache()
        let round = try finishedRound()
        let key = RoundSummaryKey(round: round)
        cache.refresh(round, key: key, bridge: nil)
        #expect(cache.summary(for: round, key: key) == nil)
    }
}
