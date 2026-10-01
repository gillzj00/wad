import Foundation
import SwiftData
import Testing
@testable import Wad

/// Wolf in the settlement, through the real engine bundle: every pair settles
/// the difference in points at the value per point, the money joins the other
/// games, and a Wolf hole that is not scored keeps the round from being final.
@MainActor
struct WolfSettlementTests {
    let container: ModelContainer
    let bridge: EngineBridge

    init() throws {
        container = try ModelContainer(for: Round.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        bridge = try EngineBridge()
    }

    func makeRound(_ draft: RoundDraft = WolfRoundTests.wolfDraft()) throws -> Round {
        let round = try draft.makeRound(using: bridge)
        container.mainContext.insert(round)
        return round
    }

    func settlement(_ round: Round) throws -> RoundSettlement {
        try RoundSettlement(round: round, bridge: bridge)
    }

    /// The example of docs/domain-model.md (Game 4) on holes 1 to 4: Zach takes
    /// Sam and wins (2 each), Sam alone loses (1 each to the others), Alex takes
    /// Jo and they lose (3 each to Zach and Sam), Jo alone wins (4). Every other
    /// hole is tied: par all round with the Wolf alone, and on 17 and 18 Alex,
    /// last alone with 1 point against 6, 5 and 5, is the Wolf without a record.
    func playDomainExample(_ round: Round) throws {
        let tests = WolfRoundTests(container: container, bridge: bridge)
        try tests.play(round, hole: 1, birdie: "zach", choice: .partner("sam"))
        try tests.play(round, hole: 2, birdie: "zach")
        try tests.play(round, hole: 3, birdie: "zach", choice: .partner("jo"))
        try tests.play(round, hole: 4, birdie: "jo")
        for hole in 5...18 { try tests.play(round, hole: hole) }
    }

    @Test func everyPairSettlesThePointDifferenceAtTheValuePerPoint() throws {
        let round = try makeRound()
        try playDomainExample(round)
        let settlement = try settlement(round)

        let wolf = try #require(settlement.wolf)
        #expect(wolf.points == ["zach": 6, "sam": 5, "alex": 1, "jo": 5])
        #expect(wolf.holes[16].wolfUserId == "alex")
        #expect(wolf.holes[17].wolfUserId == "alex")
        #expect(wolf.complete)
        #expect(settlement.isWolfComplete)
        #expect(settlement.isFinal)
        #expect(settlement.isReadyForPayment)
        #expect(settlement.unscoredWolfHoles.isEmpty)
        #expect(settlement.wolfPointCents == 100)
        #expect(settlement.isWolfUnavailable == false)

        // Zach is 1 up on Sam, 5 on Alex and 1 on Jo: +$7, which is 4 x 6 - 17.
        #expect(settlement.players.map(\.wolfCents) == [700, 300, -1300, 300])
        #expect(settlement.players.map(\.wolfCents).reduce(0, +) == 0)
        for player in settlement.players {
            #expect(player.netCents == player.skinsCents + player.wadCents + player.greeniesCents + player.wolfCents)
        }
        #expect(settlement.players.map(\.netCents).reduce(0, +) == 0)
        // The payments settle the positions, Wolf included.
        for player in settlement.players {
            let received = settlement.payments.filter { $0.toID == player.playerID }.map(\.amountCents).reduce(0, +)
            let paid = settlement.payments.filter { $0.fromID == player.playerID }.map(\.amountCents).reduce(0, +)
            #expect(received - paid == player.netCents)
        }
        #expect(SettlementText.status(settlement) == StatusLine(title: "Final", detail: "All 18 holes are scored."))
        #expect(SettlementText.games(settlement.players[0], wolf: true).hasSuffix(", Wolf +$7.00"))
        #expect(SettlementText.games(settlement.players[2]).hasSuffix("Greenies $0.00"))
        #expect(SettlementText.games(settlement.players[2]).contains("Wolf") == false)
    }

    @Test func wolfIsOneGameAmongTheOthers() throws {
        let round = try makeRound()
        try playDomainExample(round)
        let status = try RoundStatus(round: round, bridge: bridge)
        #expect(status.gameDeltas.count == 4)
        #expect(status.gameDeltas[3] == ["zach": 700, "sam": 300, "alex": -1300, "jo": 300])
        let positions = try bridge.settle(status.gameDeltas).positions
        #expect(try settlement(round).players.map(\.netCents) == round.orderedPlayers.map { positions[$0.playerID] ?? 0 })
    }

    @Test func pointValueScalesTheMoney() throws {
        var draft = WolfRoundTests.wolfDraft()
        draft.wolf.pointText = "2.50"
        let round = try makeRound(draft)
        try playDomainExample(round)
        let settlement = try settlement(round)
        #expect(settlement.wolfPointCents == 250)
        #expect(settlement.players.map(\.wolfCents) == [1750, 750, -3250, 750])
    }

    // MARK: Not final

    /// Zach alone wins hole 1 and every other hole is tied, so Sam, Alex and Jo
    /// are tied for last place after 16. All 18 holes have every score, and the
    /// round is still not final: hole 17 needs a Wolf.
    @Test func aHoleThatNeedsAWolfKeepsTheRoundFromBeingFinal() throws {
        let round = try makeRound()
        let tests = WolfRoundTests(container: container, bridge: bridge)
        for hole in 1...18 { try tests.play(round, hole: hole, birdie: hole == 1 ? "zach" : nil) }
        var settlement = try settlement(round)

        #expect(settlement.incompleteHoles.isEmpty)
        #expect(settlement.isWolfComplete == false)
        #expect(settlement.isFinal == false)
        #expect(settlement.isReadyForPayment == false)
        #expect(settlement.unscoredWolfHoles.map(\.hole) == [17])
        #expect(settlement.unscoredWolfHoles[0].status == .needsWolf)
        #expect(settlement.wolf?.holes[17].status == .pending)
        // Only scored holes count: Zach's 4 points against 0.
        #expect(settlement.players.map(\.wolfCents) == [1200, -400, -400, -400])

        #expect(SettlementText.status(settlement) == StatusLine(
            title: "Provisional, Wolf unfinished",
            detail: "Not final: Wolf: hole 17 needs a Wolf (Sam, Alex and Jo are tied for last place). "
                + "The amounts change until every Wolf hole is scored.",
            isWarning: true
        ))
        #expect(SettlementText.paymentsHeader(settlement) == "Who would pay whom (provisional)")
        #expect(WolfText.needsFixing(settlement.unscoredWolfHoles[0], name: settlement.name) == StatusLine(
            title: "Hole 17 Wolf is not scored",
            detail: "Sam, Alex and Jo are tied for last place; pick the Wolf. Tap to fix it on hole 17.",
            isWarning: true
        ))
        let payments = PaymentStatus(settlement: settlement, records: round.paidRecords)
        #expect(payments.isReadyForPayment == false)
        #expect(RoundSummary(settlement: settlement, payments: payments).progress == .wolfUnfinished)
        #expect(RoundSummary(settlement: settlement, payments: payments).progressText == "Not final: a Wolf hole is not scored")

        // The group picks Sam on 17 (tied) and then, still tied for last with Alex and Jo, Alex on 18.
        try RoundScorer(round: round).setWolf("sam", hole: 17)
        settlement = try self.settlement(round)
        #expect(settlement.isFinal == false)
        #expect(settlement.unscoredWolfHoles.map(\.hole) == [18])
        #expect(settlement.wolf?.holes[17].lastPlace == ["sam", "alex", "jo"])

        try RoundScorer(round: round).setWolf("alex", hole: 18)
        settlement = try self.settlement(round)
        #expect(settlement.isFinal)
        #expect(settlement.isReadyForPayment)
        #expect(settlement.unscoredWolfHoles.isEmpty)
        #expect(RoundSummary(settlement: settlement, payments: PaymentStatus(settlement: settlement, records: [])).progress == .final)
        // Paying works as for any final round.
        let ledger = PaymentLedger(round: round)
        try ledger.markPaid(try #require(settlement.payments.first), in: settlement, at: .now)
        #expect(PaymentStatus(settlement: settlement, records: round.paidRecords).paidCount == 1)
    }

    @Test func aMissingChoiceOrAnInvalidRecordKeepsTheRoundFromBeingFinal() throws {
        let round = try makeRound()
        try playDomainExample(round)
        let scorer = RoundScorer(round: round)
        try scorer.setWolfChoice(nil, hole: 5)
        try scorer.setWolfChoice(.partner("sam"), hole: 2)
        let settlement = try settlement(round)

        #expect(settlement.isFinal == false)
        #expect(settlement.unscoredWolfHoles.map(\.hole) == [2, 5])
        #expect(settlement.unscoredWolfHoles.map(\.status) == [.invalid, .pending])
        // Holes 17 and 18 wait for the standings; they are not something to fix themselves.
        #expect(settlement.wolf?.holes[16].status == .pending)
        #expect(SettlementText.status(settlement).detail == "Not final: Wolf: hole 2 is not scored: the partner is the Wolf; "
            + "the Wolf's choice is missing on hole 5. The amounts change until every Wolf hole is scored.")
        #expect(WolfText.needsFixing(settlement.unscoredWolfHoles[1], name: settlement.name).detail
            == "The Wolf's choice is missing. Tap to fix it on hole 5.")
    }

    /// Scores are missing: the usual provisional status, before anything about Wolf.
    @Test func missingScoresComeFirst() throws {
        let round = try makeRound()
        let tests = WolfRoundTests(container: container, bridge: bridge)
        for hole in 1...10 { try tests.play(round, hole: hole) }
        let settlement = try settlement(round)
        #expect(settlement.isFinal == false)
        #expect(SettlementText.status(settlement).title == "Provisional, through 10 holes")
        let payments = PaymentStatus(settlement: settlement, records: [])
        #expect(RoundSummary(settlement: settlement, payments: payments).progressText == "In progress, through 10 holes")
    }

    // MARK: Without Wolf

    @Test func aRoundWithoutWolfIsUnchanged() throws {
        let round = try makeRound(RoundFixtures.fourPlayerDraft())
        let settlement = try settlement(round)
        #expect(settlement.wolf == nil)
        #expect(settlement.wolfPointCents == nil)
        #expect(settlement.isWolfUnavailable == false)
        #expect(settlement.isWolfComplete)
        #expect(settlement.unscoredWolfHoles.isEmpty)
        #expect(settlement.players.allSatisfy { $0.wolfCents == 0 })
        #expect(try RoundStatus(round: round, bridge: bridge).gameDeltas.count == 3)
    }

    /// Wolf on with three players (a player left, say): the engine has no
    /// result, Wolf is reported as unavailable and is not part of the settlement.
    @Test func wolfIsUnavailableWithoutFourPlayers() throws {
        let round = try makeRound(RoundFixtures.threePlayerDraft())
        round.wolfPointCents = 100
        let settlement = try settlement(round)
        #expect(round.playsWolf)
        #expect(round.wolfInput?.teeOrder == ["zach", "sam", "alex"])
        #expect(settlement.wolf == nil)
        #expect(settlement.isWolfUnavailable)
        #expect(settlement.isWolfComplete)
        #expect(settlement.players.allSatisfy { $0.wolfCents == 0 })
        #expect(try RoundStatus(round: round, bridge: bridge).gameDeltas.count == 3)
        #expect(WolfText.unavailable.title == "Wolf needs exactly four players")
    }
}
