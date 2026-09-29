import Foundation
import SwiftData
import Testing
@testable import Wad

/// The settlement of a round through the real engine bundle. The expected
/// amounts are worked out by hand from the rules in docs/domain-model.md, in
/// integer cents; the comments show the working in dollars.
@MainActor
struct RoundSettlementTests {
    let container: ModelContainer
    let bridge: EngineBridge

    init() throws {
        container = try ModelContainer(for: Round.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        bridge = try EngineBridge()
    }

    // MARK: The full round

    /// What happened on a hole: gross scores by player where they differ from
    /// par, the Wad makers in order and the greenie winner.
    struct HolePlay {
        var gross: [String: Int] = [:]
        var wadMakers: [String] = []
        var greenie: String?
    }

    /// Course: pars 4 5 3 4 4 3 5 4 4 / 4 3 5 4 4 5 3 4 4,
    /// stroke indexes 7 11 17 3 1 15 9 5 13 / 8 18 2 10 6 12 16 4 14.
    /// Handicaps: Zach 15, Sam 7, Alex 10, Jo 7, so the group scratch is 7.
    /// Zach gets 8 ticks, on stroke indexes 1 to 8: holes 5, 12, 4, 17, 8, 14, 1, 10.
    /// Alex gets 3 ticks, on stroke indexes 1 to 3: holes 5, 12, 4.
    /// Defaults: skins $5, Wad $7 start and $2 step, greenies $5. Four players,
    /// so a winner collects from three others.
    ///
    /// Everybody makes par except where listed. Net = gross - ticks.
    ///
    /// Skins, hole by hole (the amount is what each other player pays):
    ///  1  par 4, Zach ticks: nets 3 4 4 4              Zach wins $5
    ///  2  par 5: all net 5                             push, $5 carries
    ///  3  par 3: Sam 2                                 Sam wins $10
    ///  4  par 4, Zach and Alex tick: nets 3 4 3 4      push, $5 carries
    ///  5  par 4, Zach 5 (net 4), Alex net 3            Alex wins $10
    ///  6  par 3: all net 3                             push, $5 carries
    ///  7  par 5: Jo 4                                  Jo wins $10
    ///  8  par 4, Zach 5 (net 4): all net 4             push, $5 carries
    ///  9  par 4: all net 4                             push, $10 carries
    /// 10  par 4, Zach ticks: nets 3 4 4 4              Zach wins $15
    /// 11  par 3: Alex 4, the others 3                  push, $5 carries
    /// 12  par 5, Zach 6 (net 5), Alex net 4, Jo 4      push (Alex and Jo), $10 carries
    /// 13  par 4: Sam 3                                 Sam wins $15
    /// 14  par 4, Zach ticks: nets 3 4 4 4              Zach wins $5
    /// 15  par 5: all net 5                             push, $5 carries
    /// 16  par 3: Zach 2                                Zach wins $10
    /// 17  par 4, Zach 5 (net 4): all net 4             push, $5 carries
    /// 18  par 4: Jo 3                                  Jo wins $10
    ///
    /// Skins per player = 3 x (what they won) - (what each of the others won):
    ///  Zach won 5 + 15 + 5 + 10 = 35; Sam 10 + 15 = 25; Alex 10; Jo 10 + 10 = 20.
    ///  Zach 3 x 35 - (25 + 10 + 20) = +50
    ///  Sam  3 x 25 - (35 + 10 + 20) = +10
    ///  Alex 3 x 10 - (35 + 25 + 20) = -50
    ///  Jo   3 x 20 - (35 + 25 + 10) = -10
    ///
    /// Wad, front nine: hole 2 Jo ($7) then Sam ($9), hole 6 Zach ($11), hole 9
    /// Sam ($13). Sam holds at $13: Sam +39, the others -13 each.
    /// Wad, back nine: hole 12 Alex ($7), hole 18 Alex again ($9). Alex holds
    /// at $9: Alex +27, the others -9 each.
    ///  Zach -13 - 9 = -22; Sam +39 - 9 = +30; Alex -13 + 27 = +14; Jo -13 - 9 = -22
    ///
    /// Greenies: hole 3 Sam, hole 6 Jo, hole 16 Zach, none on hole 11. Each
    /// winner gets +15 and pays 5 on the other two.
    ///  Zach +5; Sam +5; Alex -15; Jo +5
    ///
    /// Net: Zach 50 - 22 + 5 = +33; Sam 10 + 30 + 5 = +45;
    ///      Alex -50 + 14 - 15 = -51; Jo -10 - 22 + 5 = -27. They add up to 0.
    ///
    /// Payments, largest creditor against largest debtor:
    ///  Sam (45) and Alex (51): Alex pays Sam $45, Alex still owes 6
    ///  Zach (33) and Jo (27):  Jo pays Zach $27, Zach is still owed 6
    ///  Zach (6) and Alex (6):  Alex pays Zach $6
    static let fullRound: [Int: HolePlay] = [
        2: HolePlay(wadMakers: ["jo", "sam"]),
        3: HolePlay(gross: ["sam": 2], greenie: "sam"),
        5: HolePlay(gross: ["zach": 5]),
        6: HolePlay(wadMakers: ["zach"], greenie: "jo"),
        7: HolePlay(gross: ["jo": 4]),
        8: HolePlay(gross: ["zach": 5]),
        9: HolePlay(wadMakers: ["sam"]),
        11: HolePlay(gross: ["alex": 4]),
        12: HolePlay(gross: ["zach": 6, "jo": 4], wadMakers: ["alex"]),
        13: HolePlay(gross: ["sam": 3]),
        16: HolePlay(gross: ["zach": 2], greenie: "zach"),
        17: HolePlay(gross: ["zach": 5]),
        18: HolePlay(gross: ["jo": 3], wadMakers: ["alex"]),
    ]

    /// Creates the round and scores `holes` of it the way the scoring screen does.
    func makeRound(
        _ draft: RoundDraft,
        plays: [Int: HolePlay] = [:],
        holes: ClosedRange<Int>? = 1...18
    ) throws -> Round {
        let round = try draft.makeRound(using: bridge)
        container.mainContext.insert(round)
        let scorer = RoundScorer(round: round)
        guard let holes else { return round }
        for hole in holes {
            let play = plays[hole] ?? HolePlay()
            for (playerID, gross) in play.gross {
                try scorer.setGross(gross, playerID: playerID, hole: hole)
            }
            try scorer.setParForUnscored(hole: hole)
            for maker in play.wadMakers {
                try scorer.addWadMaker(playerID: maker, hole: hole)
            }
            if let greenie = play.greenie {
                try scorer.setGreenieWinner(greenie, hole: hole)
            }
        }
        return round
    }

    func result(_ settlement: RoundSettlement, _ playerID: String) throws -> RoundSettlement.PlayerResult {
        try #require(settlement.players.first { $0.playerID == playerID })
    }

    func payment(_ from: String, _ to: String, _ cents: Int, names: [String: String]) -> RoundSettlement.Payment {
        RoundSettlement.Payment(
            fromID: from, fromName: names[from] ?? "", toID: to, toName: names[to] ?? "", amountCents: cents
        )
    }

    let fourNames = ["zach": "Zach", "sam": "Sam", "alex": "Alex", "jo": "Jo"]

    @Test func fullRoundPositionsAndPayments() throws {
        let round = try makeRound(RoundFixtures.fourPlayerDraft(), plays: Self.fullRound)
        let settlement = try RoundSettlement(round: round, bridge: bridge)

        #expect(settlement.isFinal)
        #expect(settlement.incompleteHoles.isEmpty)
        #expect(settlement.completedHoleCount == 18)
        #expect(settlement.unresolvedSkinsCarryoverCents == nil)
        #expect(settlement.unpaidGreenies.isEmpty)

        #expect(settlement.players == [
            RoundSettlement.PlayerResult(
                playerID: "zach", name: "Zach", netCents: 3300, skinsCents: 5000, wadCents: -2200, greeniesCents: 500
            ),
            RoundSettlement.PlayerResult(
                playerID: "sam", name: "Sam", netCents: 4500, skinsCents: 1000, wadCents: 3000, greeniesCents: 500
            ),
            RoundSettlement.PlayerResult(
                playerID: "alex", name: "Alex", netCents: -5100, skinsCents: -5000, wadCents: 1400, greeniesCents: -1500
            ),
            RoundSettlement.PlayerResult(
                playerID: "jo", name: "Jo", netCents: -2700, skinsCents: -1000, wadCents: -2200, greeniesCents: 500
            ),
        ])

        #expect(settlement.payments == [
            payment("alex", "sam", 4500, names: fourNames),
            payment("jo", "zach", 2700, names: fourNames),
            payment("alex", "zach", 600, names: fourNames),
        ])
        #expect(settlement.payments.map(SettlementText.payment) == [
            "Alex pays Sam $45.00",
            "Jo pays Zach $27.00",
            "Alex pays Zach $6.00",
        ])
    }

    @Test func fullRoundDeltasSumToZero() throws {
        let round = try makeRound(RoundFixtures.fourPlayerDraft(), plays: Self.fullRound)
        let settlement = try RoundSettlement(round: round, bridge: bridge)

        #expect(settlement.players.map(\.netCents).reduce(0, +) == 0)
        #expect(settlement.players.map(\.skinsCents).reduce(0, +) == 0)
        #expect(settlement.players.map(\.wadCents).reduce(0, +) == 0)
        #expect(settlement.players.map(\.greeniesCents).reduce(0, +) == 0)
        for player in settlement.players {
            #expect(player.netCents == player.skinsCents + player.wadCents + player.greeniesCents)
            // What a player pays and receives is their position.
            let received = settlement.payments.filter { $0.toID == player.playerID }.map(\.amountCents).reduce(0, +)
            let paid = settlement.payments.filter { $0.fromID == player.playerID }.map(\.amountCents).reduce(0, +)
            #expect(received - paid == player.netCents)
        }
    }

    @Test func fullRoundGameDetail() throws {
        let round = try makeRound(RoundFixtures.fourPlayerDraft(), plays: Self.fullRound)
        let settlement = try RoundSettlement(round: round, bridge: bridge)

        // Skins: the winner, or nil for a push, and the amount at stake per hole.
        #expect(settlement.skins.holes.map(\.winnerUserId) == [
            "zach", nil, "sam", nil, "alex", nil, "jo", nil, nil,
            "zach", nil, nil, "sam", "zach", nil, "zach", nil, "jo",
        ])
        #expect(settlement.skins.holes.map(\.atStakeCents) == [
            500, 500, 1000, 500, 1000, 500, 1000, 500, 1000,
            1500, 500, 1000, 1500, 500, 500, 1000, 500, 1000,
        ])
        #expect(settlement.skins.holes.allSatisfy { $0.status != .pending })

        #expect(settlement.wadInstances == [
            Engine.WadInstanceResult(
                segment: .front,
                holderUserId: "sam",
                valueCents: 1300,
                makes: [
                    Engine.WadMake(hole: 2, userId: "jo", valueCents: 700),
                    Engine.WadMake(hole: 2, userId: "sam", valueCents: 900),
                    Engine.WadMake(hole: 6, userId: "zach", valueCents: 1100),
                    Engine.WadMake(hole: 9, userId: "sam", valueCents: 1300),
                ],
                complete: true
            ),
            Engine.WadInstanceResult(
                segment: .back,
                holderUserId: "alex",
                valueCents: 900,
                makes: [
                    Engine.WadMake(hole: 12, userId: "alex", valueCents: 700),
                    Engine.WadMake(hole: 18, userId: "alex", valueCents: 900),
                ],
                complete: true
            ),
        ])

        #expect(settlement.greenieHoles == [
            Engine.GreenieHoleResult(hole: 3, winnerUserId: "sam", status: .awarded),
            Engine.GreenieHoleResult(hole: 6, winnerUserId: "jo", status: .awarded),
            Engine.GreenieHoleResult(hole: 11, winnerUserId: nil, status: .none),
            Engine.GreenieHoleResult(hole: 16, winnerUserId: "zach", status: .awarded),
        ])
        #expect(settlement.greeniesAmountCents == 500)
    }

    // MARK: Open Question 1

    /// The full round, but Jo makes a 4 on hole 18: everybody nets 4 and the
    /// hole pushes with $10 at stake ($5 carried from 17). Nobody collects it.
    /// Against the full round Jo loses the 3 x $10 and the others keep their $10:
    ///  skins Zach +60, Sam +20, Alex -40, Jo -40
    ///  net   Zach 60 - 22 + 5 = +43; Sam 20 + 30 + 5 = +55;
    ///        Alex -40 + 14 - 15 = -41; Jo -40 - 22 + 5 = -57
    /// Payments: Jo pays Sam $55 (Jo still owes 2), Alex pays Zach $41 (Zach is
    /// still owed 2), Jo pays Zach $2. The $10 is in none of these.
    @Test func aPushOnTheLastHoleIsExposedAndNeverPaid() throws {
        var plays = Self.fullRound
        plays[18]?.gross = [:]
        let round = try makeRound(RoundFixtures.fourPlayerDraft(), plays: plays)
        let settlement = try RoundSettlement(round: round, bridge: bridge)

        #expect(settlement.isFinal)
        #expect(settlement.unresolvedSkinsCarryoverCents == 1000)
        #expect(settlement.skins.holes.last?.status == .pushed)

        #expect(settlement.players.map(\.skinsCents) == [6000, 2000, -4000, -4000])
        #expect(settlement.players.map(\.netCents) == [4300, 5500, -4100, -5700])
        #expect(settlement.players.map(\.skinsCents).reduce(0, +) == 0)
        #expect(settlement.players.map(\.netCents).reduce(0, +) == 0)
        #expect(settlement.payments.map(SettlementText.payment) == [
            "Jo pays Sam $55.00",
            "Alex pays Zach $41.00",
            "Jo pays Zach $2.00",
        ])
        // Everything paid is accounted for by the positions: the carryover is not in it.
        #expect(settlement.payments.map(\.amountCents).reduce(0, +) == 4300 + 5500)

        #expect(SettlementText.unresolvedCarryover(cents: 1000, lastHole: 18) == StatusLine(
            title: "$10.00 skins carryover is unresolved",
            detail: "Hole 18 was pushed. This amount is NOT paid out and is not in any total. "
                + "It is awaiting a rules decision.",
            isWarning: true
        ))
    }

    /// A carryover in the middle of the round is not unresolved: it goes to the next hole.
    @Test func aCarryoverMidRoundIsNotUnresolved() throws {
        let round = try makeRound(RoundFixtures.fourPlayerDraft(), plays: Self.fullRound, holes: 1...9)
        let settlement = try RoundSettlement(round: round, bridge: bridge)

        #expect(settlement.skins.carryOutCents == 1000)
        #expect(settlement.unresolvedSkinsCarryoverCents == nil)
    }

    // MARK: Provisional

    /// The first 10 holes of the full round.
    ///  Skins: Zach won 5 + 15 = 20, Sam 10, Alex 10, Jo 10 from each other player.
    ///   Zach 3 x 20 - 30 = +30; Sam, Alex and Jo 3 x 10 - 40 = -10 each
    ///  Wad: the front nine is finished, Sam holds at $13: Sam +39, the others -13.
    ///   The back nine is not finished, so nothing is collected for it.
    ///  Greenies: hole 3 Sam, hole 6 Jo: Sam +10, Jo +10, Zach -10, Alex -10
    ///  Net: Zach 30 - 13 - 10 = +7; Sam -10 + 39 + 10 = +39;
    ///       Alex -10 - 13 - 10 = -33; Jo -10 - 13 + 10 = -13
    ///  Payments: Alex pays Sam $33 (Sam is still owed 6), Jo pays Zach $7 (Jo
    ///  still owes 6), Jo pays Sam $6.
    @Test func aRoundInProgressIsProvisional() throws {
        let round = try makeRound(RoundFixtures.fourPlayerDraft(), plays: Self.fullRound, holes: 1...10)
        // A make on the back nine is recorded, and not collected before hole 18.
        try RoundScorer(round: round).addWadMaker(playerID: "jo", hole: 10)
        let settlement = try RoundSettlement(round: round, bridge: bridge)

        #expect(settlement.isFinal == false)
        #expect(settlement.completedHoleCount == 10)
        #expect(settlement.incompleteHoles == Array(11...18))
        #expect(settlement.isScoredInOrder)
        #expect(settlement.unresolvedSkinsCarryoverCents == nil)

        #expect(settlement.players.map(\.skinsCents) == [3000, -1000, -1000, -1000])
        #expect(settlement.players.map(\.wadCents) == [-1300, 3900, -1300, -1300])
        #expect(settlement.players.map(\.greeniesCents) == [-1000, 1000, -1000, 1000])
        #expect(settlement.players.map(\.netCents) == [700, 3900, -3300, -1300])
        #expect(settlement.payments.map(SettlementText.payment) == [
            "Alex pays Sam $33.00",
            "Jo pays Zach $7.00",
            "Jo pays Sam $6.00",
        ])

        let back = try #require(settlement.wadInstances.last)
        #expect(back.holderUserId == "jo")
        #expect(back.valueCents == 700)
        #expect(back.complete == false)
        #expect(settlement.skins.holes[10].status == .pending)

        #expect(SettlementText.status(settlement) == StatusLine(
            title: "Provisional, through 10 holes",
            detail: "Not final: scores are missing on holes 11, 12, 13, 14, 15, 16, 17, 18. "
                + "The amounts change as holes are scored. The Wad is collected only when its nine is finished.",
            isWarning: true
        ))
        #expect(SettlementText.paymentsHeader(settlement) == "Who would pay whom (provisional)")
    }

    /// Hole 1 is scored and hole 2 is not: "through" would be wrong for holes 3 and 4.
    @Test func holesScoredOutOfOrderAreCounted() throws {
        let round = try makeRound(RoundFixtures.fourPlayerDraft(), plays: Self.fullRound, holes: 1...4)
        try RoundScorer(round: round).setGross(nil, playerID: "sam", hole: 2)
        let settlement = try RoundSettlement(round: round, bridge: bridge)

        #expect(settlement.isFinal == false)
        #expect(settlement.isScoredInOrder == false)
        #expect(settlement.incompleteHoles == [2] + Array(5...18))
        #expect(SettlementText.status(settlement).title == "Provisional, 3 of 18 holes scored")
        // Skins stop at the first hole that is not scored: only hole 1 is paid.
        #expect(settlement.players.map(\.skinsCents) == [1500, -500, -500, -500])
    }

    @Test func aRoundWithoutScoresOwesNothing() throws {
        let round = try makeRound(RoundFixtures.fourPlayerDraft(), holes: nil)
        let settlement = try RoundSettlement(round: round, bridge: bridge)

        #expect(settlement.isFinal == false)
        #expect(settlement.completedHoleCount == 0)
        #expect(settlement.players.allSatisfy { $0.netCents == 0 })
        #expect(settlement.payments.isEmpty)
        #expect(SettlementText.status(settlement).title == "Provisional, no holes scored")
        #expect(SettlementText.noPayments(settlement) == "Nobody owes anything so far")
    }

    // MARK: Greenies that are not paid

    /// The full round, then Sam's 2 on hole 3 is corrected to a 4. The greenie
    /// recorded for Sam is invalid and is not paid:
    ///  greenies: hole 6 Jo, hole 16 Zach: Zach +10, Jo +10, Sam -10, Alex -10
    /// Hole 3 is then a push at net 3 (Zach, Alex, Jo), which the engine scores.
    @Test func anInvalidGreenieIsNotPaid() throws {
        let round = try makeRound(RoundFixtures.fourPlayerDraft(), plays: Self.fullRound)
        try RoundScorer(round: round).setGross(4, playerID: "sam", hole: 3)
        let settlement = try RoundSettlement(round: round, bridge: bridge)

        #expect(settlement.unpaidGreenies == [
            Engine.GreenieHoleResult(hole: 3, winnerUserId: "sam", status: .invalid),
        ])
        #expect(settlement.players.map(\.greeniesCents) == [1000, -1000, -1000, 1000])
        #expect(settlement.players.map(\.netCents).reduce(0, +) == 0)
        for player in settlement.players {
            #expect(player.netCents == player.skinsCents + player.wadCents + player.greeniesCents)
        }

        #expect(SettlementText.unpaidGreenie(settlement.unpaidGreenies[0], name: settlement.name) == StatusLine(
            title: "Hole 3 greenie is not paid",
            detail: "Sam did not score par or better. Tap to fix it on hole 3.",
            isWarning: true
        ))
    }

    // MARK: Nothing owed

    /// Two players with the same handicap make par everywhere: every hole
    /// pushes, nobody holds the Wad and there is no greenie. All positions are
    /// $0 and there is no payment. The 18 pushed skins ($90) are unresolved.
    @Test func aRoundOfZeroResultsHasNoPayments() throws {
        var draft = RoundFixtures.unratedDraft()
        draft.players[0].courseHandicapText = "7"
        let round = try makeRound(draft)
        let settlement = try RoundSettlement(round: round, bridge: bridge)

        #expect(settlement.isFinal)
        #expect(settlement.players.allSatisfy {
            $0.netCents == 0 && $0.skinsCents == 0 && $0.wadCents == 0 && $0.greeniesCents == 0
        })
        #expect(settlement.payments.isEmpty)
        #expect(settlement.unresolvedSkinsCarryoverCents == 9000)
        #expect(SettlementText.noPayments(settlement) == "Nobody owes anything")
        #expect(SettlementText.status(settlement) == StatusLine(title: "Final", detail: "All 18 holes are scored."))
    }

    // MARK: The UI test scenarios

    /// The round the UI walkthrough scores by tapping. Every hole is a par 4
    /// except the third; Zach gets a tick on holes 1 to 8. Pars except where listed.
    ///
    /// Skins (amount from each of the two others):
    ///  1  Zach 5 (net 4), 4, 4          push, $5 carries
    ///  2  nets 3 4 4                    Zach wins $10
    ///  3  par 3: Zach 3 (net 2), Alex 4 Zach wins $5
    ///  4  nets 3 4 4                    Zach wins $5
    ///  5  Sam 3, Zach net 3             push, $5 carries
    ///  6  nets 3 4 4                    Zach wins $10
    ///  7  Alex 3, Zach net 3            push, $5 carries
    ///  8  Zach 5 (net 4)                push, $10 carries
    ///  9  Alex 3                        Alex wins $15
    /// 10  Sam 3                         Sam wins $5
    /// 11, 12  all 4                     push, push, $10 carries
    /// 13  Zach 3                        Zach wins $15
    /// 14, 15  all 4                     push, push, $10 carries
    /// 16  Sam 3                         Sam wins $15
    /// 17  all 4                         push, $5 carries
    /// 18  Alex 3                        Alex wins $10
    ///  Zach won 10 + 5 + 5 + 10 + 15 = 45; Sam 5 + 15 = 20; Alex 15 + 10 = 25.
    ///  Zach 2 x 45 - (20 + 25) = +45; Sam 2 x 20 - (45 + 25) = -30;
    ///  Alex 2 x 25 - (45 + 20) = -15
    /// Wad front: hole 1 Sam ($7), Zach ($9); hole 3 Alex ($11); hole 7 Sam
    ///  ($13): Sam +26, Zach -13, Alex -13. Back: hole 15 Alex ($7): Alex +14,
    ///  Zach -7, Sam -7. Wad: Zach -20, Sam +19, Alex +1
    /// Greenies: hole 3 Sam: Sam +10, Zach -5, Alex -5
    /// Net: Zach 45 - 20 - 5 = +20; Sam -30 + 19 + 10 = -1; Alex -15 + 1 - 5 = -19
    /// Payments: Alex pays Zach $19, Sam pays Zach $1.
    @Test func theWalkthroughRound() throws {
        let plays: [Int: HolePlay] = [
            1: HolePlay(gross: ["zach": 5], wadMakers: ["sam", "zach"]),
            3: HolePlay(gross: ["alex": 4], wadMakers: ["alex"], greenie: "sam"),
            5: HolePlay(gross: ["sam": 3]),
            7: HolePlay(gross: ["alex": 3], wadMakers: ["sam"]),
            8: HolePlay(gross: ["zach": 5]),
            9: HolePlay(gross: ["alex": 3]),
            10: HolePlay(gross: ["sam": 3]),
            13: HolePlay(gross: ["zach": 3]),
            15: HolePlay(wadMakers: ["alex"]),
            16: HolePlay(gross: ["sam": 3]),
            18: HolePlay(gross: ["alex": 3]),
        ]
        let round = try makeRound(RoundFixtures.walkthroughDraft(), plays: plays)
        let settlement = try RoundSettlement(round: round, bridge: bridge)

        #expect(settlement.isFinal)
        #expect(settlement.unresolvedSkinsCarryoverCents == nil)
        #expect(settlement.players.map(\.skinsCents) == [4500, -3000, -1500])
        #expect(settlement.players.map(\.wadCents) == [-2000, 1900, 100])
        #expect(settlement.players.map(\.greeniesCents) == [-500, 1000, -500])
        #expect(settlement.players.map(\.netCents) == [2000, -100, -1900])
        #expect(settlement.payments.map(SettlementText.payment) == ["Alex pays Zach $19.00", "Sam pays Zach $1.00"])
        #expect(settlement.players.map(SettlementText.games) == [
            "Zach: Skins +$45.00, Wad -$20.00, Greenies -$5.00",
            "Sam: Skins -$30.00, Wad +$19.00, Greenies +$10.00",
            "Alex: Skins -$15.00, Wad +$1.00, Greenies -$5.00",
        ])
    }

    /// `DebugRounds.finalPush`: pars everywhere, so Zach wins the holes he has
    /// a tick on (1, 4, 5, 8, 10, 12, 14) and the others push; on 17 his bogey
    /// nets 4 and pushes too, so holes 15 to 18 leave $20 unresolved.
    ///  Skins from each: hole 1 $5, 4 $15, 5 $5, 8 $15, 10 $10, 12 $10, 14 $10 = $70
    ///   Zach +140, Sam -70, Alex -70
    ///  Wad front: Sam holds at $7: Sam +14, Zach -7, Alex -7. Back: nobody.
    ///  Greenies: hole 3 Alex: Alex +10, Zach -5, Sam -5
    ///  Net: Zach 140 - 7 - 5 = +128; Sam -70 + 14 - 5 = -61; Alex -70 - 7 + 10 = -67
    ///  Payments: Alex pays Zach $67, Sam pays Zach $61.
    @Test func theSeededRoundWithAnUnresolvedCarryover() throws {
        let round = try DebugRounds.finalPush(using: bridge)
        container.mainContext.insert(round)
        let settlement = try RoundSettlement(round: round, bridge: bridge)

        #expect(settlement.isFinal)
        #expect(settlement.unresolvedSkinsCarryoverCents == 2000)
        #expect(settlement.players.map(\.skinsCents) == [14000, -7000, -7000])
        #expect(settlement.players.map(\.wadCents) == [-700, 1400, -700])
        #expect(settlement.players.map(\.greeniesCents) == [-500, -500, 1000])
        #expect(settlement.players.map(\.netCents) == [12800, -6100, -6700])
        #expect(settlement.payments.map(SettlementText.payment) == ["Alex pays Zach $67.00", "Sam pays Zach $61.00"])
    }

    // MARK: Wording

    @Test func wordsAmountsWithTheirSign() {
        #expect(SettlementText.signed(4500) == "+$45.00")
        #expect(SettlementText.signed(-2050) == "-$20.50")
        #expect(SettlementText.signed(0) == "$0.00")
        #expect(SettlementText.position(2000) == "Won $20.00")
        #expect(SettlementText.position(-1905) == "Owes $19.05")
        #expect(SettlementText.position(0) == "Even")
        #expect(SettlementText.holes([4]) == "hole 4")
        #expect(SettlementText.holes([4, 9]) == "holes 4, 9")
        #expect(SettlementText.wadMake(
            Engine.WadMake(hole: 5, userId: "b", valueCents: 900), name: { $0.uppercased() }
        ) == "Hole 5: B holds at $9.00")
    }
}
