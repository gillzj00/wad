import Foundation
import SwiftData
import Testing
@testable import Wad

/// The games' state for a partially scored round, through the real engine
/// bundle, and how it is worded and laid out on the scorecard.
@MainActor
struct RoundStatusTests {
    let container: ModelContainer
    let bridge: EngineBridge
    let round: Round
    let scorer: RoundScorer

    let names = ["zach": "Zach", "sam": "Sam", "alex": "Alex"]
    func name(_ id: String) -> String { names[id] ?? id }

    /// Zach (15) gets a tick on stroke indexes 1 to 8; Sam and Alex (7) get none.
    /// Hole 1 (par 4, stroke index 7): 5, 4, 4 nets 4, 4, 4 and pushes.
    /// Hole 2 (par 5, stroke index 11): Zach's 5 beats two 6s for $10.
    /// Hole 3 (par 3): Alex has no score yet. Hole 4 onwards: nothing.
    init() throws {
        container = try ModelContainer(for: Round.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        bridge = try EngineBridge()
        round = try RoundFixtures.threePlayerDraft().makeRound(using: bridge)
        container.mainContext.insert(round)
        scorer = RoundScorer(round: round)

        try scorer.setGross(5, playerID: "zach", hole: 1)
        try scorer.setGross(4, playerID: "sam", hole: 1)
        try scorer.setGross(4, playerID: "alex", hole: 1)
        try scorer.addWadMaker(playerID: "sam", hole: 1)
        try scorer.addWadMaker(playerID: "zach", hole: 1)

        try scorer.setGross(5, playerID: "zach", hole: 2)
        try scorer.setGross(6, playerID: "sam", hole: 2)
        try scorer.setGross(6, playerID: "alex", hole: 2)
        try scorer.addWadMaker(playerID: "zach", hole: 2)

        try scorer.setGross(3, playerID: "zach", hole: 3)
        try scorer.setGross(4, playerID: "sam", hole: 3)
        try scorer.setGreenieWinner("zach", hole: 3)
    }

    @Test func ticksAndNetScoresComeFromTheEngine() throws {
        let status = try RoundStatus(round: round, bridge: bridge)

        #expect(status.ticks(playerID: "zach", hole: 1) == 1)
        #expect(status.ticks(playerID: "zach", hole: 2) == 0)
        #expect(status.ticks(playerID: "sam", hole: 1) == 0)
        #expect(status.ticks(playerID: "nobody", hole: 1) == nil)

        #expect(status.net(playerID: "zach", hole: 1) == 4)
        #expect(status.net(playerID: "sam", hole: 1) == 4)
        #expect(status.net(playerID: "zach", hole: 2) == 5)
        // Not every player has a score on hole 3 yet.
        #expect(status.net(playerID: "zach", hole: 3) == nil)
    }

    @Test func skinsStatusOfAPartiallyScoredRound() throws {
        let status = try RoundStatus(round: round, bridge: bridge)

        #expect(status.skinsHole(1) == Engine.SkinHoleResult(
            hole: 1, status: .pushed, carriedInCents: 0, atStakeCents: 500, winnerUserId: nil,
            net: ["zach": 4, "sam": 4, "alex": 4]
        ))
        #expect(status.skinsHole(2) == Engine.SkinHoleResult(
            hole: 2, status: .won, carriedInCents: 500, atStakeCents: 1000, winnerUserId: "zach",
            net: ["zach": 5, "sam": 6, "alex": 6]
        ))
        #expect(status.skinsHole(3) == Engine.SkinHoleResult(
            hole: 3, status: .pending, carriedInCents: 0, atStakeCents: 500, winnerUserId: nil, net: nil
        ))
        #expect(status.skinsHole(4) == Engine.SkinHoleResult(
            hole: 4, status: .pending, carriedInCents: nil, atStakeCents: nil, winnerUserId: nil, net: nil
        ))
        #expect(status.skins.deltas == ["zach": 2000, "sam": -1000, "alex": -1000])
        #expect(status.skins.complete == false)
    }

    @Test func wadStatusOfTheCurrentNine() throws {
        let status = try RoundStatus(round: round, bridge: bridge)

        let front = try #require(status.wadInstance(hole: 3))
        #expect(front.segment == .front)
        #expect(front.holderUserId == "zach")
        #expect(front.valueCents == 1100)
        #expect(front.complete == false)
        #expect(status.wadInstance(hole: 9) == front)

        #expect(status.wadMakes(hole: 1) == [
            Engine.WadMake(hole: 1, userId: "sam", valueCents: 700),
            Engine.WadMake(hole: 1, userId: "zach", valueCents: 900),
        ])
        #expect(status.wadMakes(hole: 2) == [Engine.WadMake(hole: 2, userId: "zach", valueCents: 1100)])
        #expect(status.wadMakes(hole: 3).isEmpty)

        let back = try #require(status.wadInstance(hole: 10))
        #expect(back.segment == .back)
        #expect(back.holderUserId == nil)
        #expect(back.valueCents == 700)

        // Nothing is paid before the nine is finished.
        #expect(status.wad.deltas == ["zach": 0, "sam": 0, "alex": 0])
    }

    @Test func greenieStatusAndGameDeltas() throws {
        let status = try RoundStatus(round: round, bridge: bridge)

        #expect(status.greenieHole(3) == Engine.GreenieHoleResult(hole: 3, winnerUserId: "zach", status: .awarded))
        #expect(status.greenieHole(6) == Engine.GreenieHoleResult(hole: 6, winnerUserId: nil, status: .none))
        #expect(status.greenieHole(1) == nil)
        #expect(status.greenies.deltas == ["zach": 1000, "sam": -500, "alex": -500])

        #expect(status.gameDeltas == [status.skins.deltas, status.wad.deltas, status.greenies.deltas])
        let settlement = try bridge.settle(status.gameDeltas)
        #expect(settlement.positions == ["zach": 3000, "sam": -1500, "alex": -1500])
    }

    @Test func wordsTheSkinsStatus() throws {
        let status = try RoundStatus(round: round, bridge: bridge)

        #expect(ScoringText.skins(try #require(status.skinsHole(1)), lastHole: 18, carryover: true, name: name) == StatusLine(
            title: "Pushed",
            detail: "Nothing carried in. $5.00 carries to hole 2."
        ))
        #expect(ScoringText.skins(try #require(status.skinsHole(2)), lastHole: 18, carryover: true, name: name) == StatusLine(
            title: "Zach wins $10.00 from each other player",
            detail: "$10.00 at stake. $5.00 carried in."
        ))
        #expect(ScoringText.skins(try #require(status.skinsHole(3)), lastHole: 18, carryover: true, name: name) == StatusLine(
            title: "$5.00 at stake",
            detail: "Nothing carried in. Waiting for every player's score."
        ))
        #expect(ScoringText.skins(try #require(status.skinsHole(4)), lastHole: 18, carryover: true, name: name) == StatusLine(
            title: "Waiting for earlier holes",
            detail: "The amount at stake is known once every earlier hole is scored."
        ))
    }

    /// With carryover off the same holes: the push on 1 pays nothing, and Zach
    /// wins hole 2 for the base only.
    @Test func wordsTheSkinsStatusWithoutCarryover() throws {
        round.skinsCarryover = false
        let status = try RoundStatus(round: round, bridge: bridge)

        #expect(status.skins.holes[1].atStakeCents == 500)
        #expect(status.skins.deltas == ["zach": 1000, "sam": -500, "alex": -500])
        #expect(ScoringText.skins(try #require(status.skinsHole(1)), lastHole: 18, carryover: false, name: name) == StatusLine(
            title: "Pushed",
            detail: "Carryover is off: nothing is paid. Hole 2 is worth $5.00 again."
        ))
        #expect(ScoringText.skins(try #require(status.skinsHole(2)), lastHole: 18, carryover: false, name: name) == StatusLine(
            title: "Zach wins $5.00 from each other player",
            detail: "$5.00 at stake."
        ))
        #expect(ScoringText.skins(try #require(status.skinsHole(3)), lastHole: 18, carryover: false, name: name) == StatusLine(
            title: "$5.00 at stake",
            detail: "Waiting for every player's score."
        ))
        #expect(ScoringText.skins(try #require(status.skinsHole(4)), lastHole: 18, carryover: false, name: name) == StatusLine(
            title: "Waiting for earlier holes",
            detail: "The amount at stake is known once every earlier hole is scored."
        ))
    }

    /// Open Question 1: a push on the last hole is shown and never paid.
    @Test func aPushOnTheLastHoleIsShownAsUnresolved() throws {
        for hole in 1...18 { try scorer.setParForUnscored(hole: hole) }
        try scorer.setGross(4, playerID: "alex", hole: 18)
        try scorer.setGross(4, playerID: "sam", hole: 18)
        try scorer.setGross(5, playerID: "zach", hole: 18)

        let status = try RoundStatus(round: round, bridge: bridge)
        let last = try #require(status.skinsHole(18))
        #expect(last.status == .pushed)
        #expect(status.skins.complete)
        #expect(status.skins.carryOutCents == last.atStakeCents)
        #expect(status.skins.deltas.values.reduce(0, +) == 0)

        let line = ScoringText.skins(last, lastHole: 18, carryover: true, name: name)
        #expect(line.title == "Pushed")
        let atStake = ScoringText.dollars(try #require(last.atStakeCents))
        #expect(line.detail?.hasSuffix("Last hole: \(atStake) is unresolved and is not paid out.") == true)
    }

    /// Without carryover a push on the last hole leaves nothing unresolved.
    @Test func aPushOnTheLastHoleWithoutCarryoverIsResolved() throws {
        round.skinsCarryover = false
        for hole in 1...18 { try scorer.setParForUnscored(hole: hole) }
        try scorer.setGross(4, playerID: "alex", hole: 18)
        try scorer.setGross(4, playerID: "sam", hole: 18)
        try scorer.setGross(5, playerID: "zach", hole: 18)

        let status = try RoundStatus(round: round, bridge: bridge)
        let last = try #require(status.skinsHole(18))
        #expect(last.status == .pushed)
        #expect(last.carriedInCents == 0)
        #expect(last.atStakeCents == 500)
        #expect(status.skins.complete)
        #expect(status.skins.carryOutCents == 0)
        #expect(ScoringText.skins(last, lastHole: 18, carryover: false, name: name) == StatusLine(
            title: "Pushed",
            detail: "Carryover is off: nothing is paid."
        ))

        let settlement = try RoundSettlement(round: round, bridge: bridge)
        #expect(settlement.skinsCarryover == false)
        #expect(settlement.unresolvedSkinsCarryoverCents == nil)
        #expect(settlement.isFinal)
    }

    @Test func wordsTheWadAndGreenieStatus() throws {
        let status = try RoundStatus(round: round, bridge: bridge)

        #expect(ScoringText.wad(
            try #require(status.wadInstance(hole: 1)), makesOnHole: status.wadMakes(hole: 1), name: name
        ) == StatusLine(
            title: "Zach holds the Wad at $11.00",
            detail: "Front nine. Collected from each other player after hole 9. This hole: Sam $7.00, Zach $9.00."
        ))
        #expect(ScoringText.wad(
            try #require(status.wadInstance(hole: 10)), makesOnHole: status.wadMakes(hole: 10), name: name
        ) == StatusLine(
            title: "Nobody holds the Wad",
            detail: "Back nine. The first make takes it at $7.00."
        ))

        #expect(ScoringText.greenie(try #require(status.greenieHole(3)), amountCents: 500, name: name) == StatusLine(
            title: "Zach wins the greenie",
            detail: "$5.00 from each other player."
        ))
        #expect(ScoringText.greenie(try #require(status.greenieHole(6)), amountCents: 500, name: name) == StatusLine(
            title: "No greenie",
            detail: "Worth $5.00 from each other player."
        ))
        #expect(ScoringText.ticks(0) == "No ticks")
        #expect(ScoringText.ticks(1) == "1 tick")
        #expect(ScoringText.ticks(2) == "2 ticks")
        #expect(ScoringText.dollars(1350) == "$13.50")
    }

    @Test func scorecardAddsUpTheStrokesEntered() throws {
        try scorer.setGross(4, playerID: "zach", hole: 10)
        let scorecard = Scorecard(round: round)

        #expect(scorecard.completedHoleCount == 2)
        #expect(scorecard.holeCount == 18)
        #expect(scorecard.par(on: Round.frontNine) == 36)
        #expect(scorecard.par(on: Round.backNine) == 36)
        #expect(scorecard.rows.map(\.name) == ["Zach", "Sam", "Alex"])

        let zach = scorecard.rows[0]
        #expect(zach.gross == [1: 5, 2: 5, 3: 3, 10: 4])
        #expect(zach.out == 13)
        #expect(zach.back == 4)
        #expect(zach.total == 17)

        let alex = scorecard.rows[2]
        #expect(alex.gross == [1: 4, 2: 6])
        #expect(alex.out == 10)
        #expect(alex.back == nil)
        #expect(alex.total == 10)
    }

    @Test func scorecardReadsEachRowAsItIsPrinted() throws {
        try scorer.setGross(4, playerID: "zach", hole: 10)
        let scorecard = Scorecard(round: round)

        let zach = scorecard.rows[0]
        #expect(zach.readout(on: Round.frontNine, showsTotal: false) == "Zach, 5, 5, 3, -, -, -, -, -, -, 13")
        #expect(zach.readout(on: Round.backNine, showsTotal: true) == "Zach, 4, -, -, -, -, -, -, -, -, 4, 17")
        let alex = scorecard.rows[2]
        #expect(alex.readout(on: Round.backNine, showsTotal: true) == "Alex, -, -, -, -, -, -, -, -, -, -, 10")
    }

    @Test func scorecardEditsAPlayersScoreOnAHoleOfTheRound() {
        let scorecard = Scorecard(round: round)

        #expect(scorecard.isEditable(playerID: "zach", hole: 1))
        #expect(scorecard.isEditable(playerID: "alex", hole: 3))
        #expect(scorecard.isEditable(playerID: "sam", hole: 18))
        #expect(!scorecard.isEditable(playerID: "zach", hole: 0))
        #expect(!scorecard.isEditable(playerID: "zach", hole: 19))
        #expect(!scorecard.isEditable(playerID: "jo", hole: 1))
    }
}
