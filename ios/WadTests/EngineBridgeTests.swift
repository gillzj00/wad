import Foundation
import Testing
@testable import Wad

/// Runs the worked examples from docs/domain-model.md through the real
/// engines.js bundle. Amounts are integer cents.
struct EngineBridgeTests {
    // A par-72 course. Stroke index 1 is hole 5, 2 is hole 12, and so on.
    static let pars = [4, 5, 3, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 4, 5, 3, 4, 4]
    static let strokeIndexes = [7, 11, 17, 3, 1, 15, 9, 5, 13, 8, 18, 2, 10, 6, 12, 16, 4, 14]
    static let course18 = (0..<18).map { Engine.HoleInfo(hole: $0 + 1, par: pars[$0], strokeIndex: strokeIndexes[$0]) }
    static let front9 = Array(course18.prefix(9))

    static let four = ["A", "B", "C", "D"]

    static func players(_ ids: [String], courseHandicap: Int = 10) -> [Engine.Player] {
        ids.map { Engine.Player(userId: $0, displayName: $0, courseHandicap: courseHandicap) }
    }

    static func scores(hole: Int, _ gross: [String: Int]) -> [Engine.Score] {
        gross.map { Engine.Score(userId: $0.key, hole: hole, gross: $0.value) }
    }

    let bridge: EngineBridge

    init() throws {
        bridge = try EngineBridge()
    }

    @Test func wadExampleHolderCollectsFromEach() throws {
        let result = try bridge.scoreWad(Engine.WadInput(
            players: Self.four,
            holes: Self.front9,
            scores: Self.scores(hole: 9, ["A": 4, "B": 4, "C": 4, "D": 4]),
            holeEvents: [
                Engine.HoleEvents(hole: 2, wadMakers: ["A"]),
                Engine.HoleEvents(hole: 5, wadMakers: ["B", "C"]),
                Engine.HoleEvents(hole: 7, wadMakers: ["C"]),
            ],
            startCents: 700,
            stepCents: 200
        ))

        #expect(result.instances.count == 1)
        let front = try #require(result.instances.first)
        #expect(front.segment == .front)
        #expect(front.makes == [
            Engine.WadMake(hole: 2, userId: "A", valueCents: 700),
            Engine.WadMake(hole: 5, userId: "B", valueCents: 900),
            Engine.WadMake(hole: 5, userId: "C", valueCents: 1100),
            Engine.WadMake(hole: 7, userId: "C", valueCents: 1300),
        ])
        #expect(front.holderUserId == "C")
        #expect(front.valueCents == 1300)
        #expect(front.complete)
        #expect(result.deltas == ["A": -1300, "B": -1300, "C": 3900, "D": -1300])
        #expect(result.ignored.isEmpty)
    }

    @Test func skinsExampleTwoPushesThenAWinsFifteenFromEach() throws {
        let result = try bridge.scoreSkins(Engine.SkinsInput(
            players: Self.players(Self.four),
            holes: Self.course18,
            scores: Self.scores(hole: 1, ["A": 4, "B": 4, "C": 5, "D": 5])
                + Self.scores(hole: 2, ["A": 5, "B": 6, "C": 5, "D": 6])
                + Self.scores(hole: 3, ["A": 3, "B": 4, "C": 4, "D": 4])
                + Self.scores(hole: 4, ["A": 4, "B": 4, "C": 4, "D": 4]),
            baseCents: 500
        ))

        let holes = result.holes
        #expect(holes.count == 18)
        #expect(holes[0].status == .pushed)
        #expect(holes[0].atStakeCents == 500)
        #expect(holes[1].status == .pushed)
        #expect(holes[1].carriedInCents == 500)
        #expect(holes[1].atStakeCents == 1000)
        #expect(holes[2].status == .won)
        #expect(holes[2].winnerUserId == "A")
        #expect(holes[2].carriedInCents == 1000)
        #expect(holes[2].atStakeCents == 1500)
        #expect(holes[2].net == ["A": 3, "B": 4, "C": 4, "D": 4])
        #expect(holes[3].carriedInCents == 0)
        #expect(holes[3].atStakeCents == 500)
        #expect(holes[4].status == .pending)
        #expect(result.deltas == ["A": 4500, "B": -1500, "C": -1500, "D": -1500])
        #expect(!result.complete)
    }

    @Test func skinsPushOnTheLastHoleIsExposedAndNotPaid() throws {
        // A wins holes 1-16 outright; 17 and 18 are pushed.
        let scores = Self.course18.flatMap { hole in
            Self.scores(hole: hole.hole, ["A": hole.hole <= 16 ? 3 : 4, "B": 4, "C": 4, "D": 4])
        }
        let result = try bridge.scoreSkins(Engine.SkinsInput(
            players: Self.players(Self.four),
            holes: Self.course18,
            scores: scores,
            baseCents: 500
        ))

        let last = try #require(result.holes.last)
        #expect(last.hole == 18)
        #expect(last.status == .pushed)
        #expect(last.winnerUserId == nil)
        #expect(last.carriedInCents == 500)
        #expect(last.atStakeCents == 1000)
        #expect(result.complete)
        #expect(result.carryOutCents == 1000)
        // Only the 16 skins that were won are paid: 16 * $5 from each of three.
        #expect(result.deltas == ["A": 24000, "B": -8000, "C": -8000, "D": -8000])
        #expect(result.deltas.values.reduce(0, +) == 0)
    }

    @Test func greeniesExampleWinnerCollectsFromEach() throws {
        let result = try bridge.scoreGreenies(Engine.GreeniesInput(
            players: ["A", "B", "C"],
            holes: Self.front9,
            scores: Self.scores(hole: 3, ["A": 3, "B": 3, "C": 4]),
            holeEvents: [Engine.HoleEvents(hole: 3, greenieWinner: "A")],
            amountCents: 500
        ))

        #expect(result.holes == [
            Engine.GreenieHoleResult(hole: 3, winnerUserId: "A", status: .awarded),
            Engine.GreenieHoleResult(hole: 6, winnerUserId: nil, status: Engine.GreenieStatus.none),
        ])
        #expect(result.deltas == ["A": 1000, "B": -500, "C": -500])
    }

    @Test func allocatesEightTicksForFifteenVersusSeven() throws {
        let ticks = try bridge.allocateTicks(
            players: [
                Engine.Player(userId: "zach", displayName: "Zach", courseHandicap: 15),
                Engine.Player(userId: "friend", displayName: "Friend", courseHandicap: 7),
            ],
            holes: Self.course18
        )

        let zach = try #require(ticks["zach"])
        let friend = try #require(ticks["friend"])
        #expect(zach.count == 18)
        #expect(zach.values.reduce(0, +) == 8)
        for hole in Self.course18 {
            #expect(zach[hole.hole] == (hole.strokeIndex <= 8 ? 1 : 0))
            #expect(friend[hole.hole] == 0)
        }
    }

    // The same cases as backend/test/engines/handicap.test.ts, plus the neutral 15.
    @Test(arguments: [
        (15.0, Engine.TeeRating(slope: 113, courseRating: 72.0, par: 72), 15),
        (12.0, Engine.TeeRating(slope: 113, courseRating: 72.0, par: 72), 12),
        // 15.4 * 131/113 = 17.853..., + (72.5 - 72) = 18.353... -> 18
        (15.4, Engine.TeeRating(slope: 131, courseRating: 72.5, par: 72), 18),
        (-2.0, Engine.TeeRating(slope: 113, courseRating: 71.0, par: 72), -3),
    ])
    func courseHandicapAppliesSlopeAndRating(handicapIndex: Double, tee: Engine.TeeRating, expected: Int) throws {
        #expect(try bridge.courseHandicap(handicapIndex: handicapIndex, tee: tee) == expected)
    }

    @Test func settleReducesGameDeltasToPairwiseTransfers() throws {
        let skins = ["A": 4500, "B": -1500, "C": -1500, "D": -1500]
        let wad = ["A": -1300, "B": -1300, "C": 3900, "D": -1300]

        let settlement = try bridge.settle([skins, wad])

        #expect(settlement.positions == ["A": 3200, "B": -2800, "C": 2400, "D": -2800])
        #expect(settlement.transfers == [
            Engine.Transfer(from: "B", to: "A", amountCents: 2800),
            Engine.Transfer(from: "D", to: "C", amountCents: 2400),
            Engine.Transfer(from: "D", to: "A", amountCents: 400),
        ])
    }

    @Test func javaScriptExceptionIsThrownAsSwiftError() throws {
        #expect(throws: EngineError.javaScriptException(message: "Error: deltas must sum to zero, got 100")) {
            try bridge.settle([["A": 100, "B": 0]])
        }
        #expect(throws: EngineError.javaScriptException(message: "Error: no holes to allocate ticks over")) {
            try bridge.allocateTicks(players: Self.players(["A", "B"]), holes: [])
        }

        // The bridge is still usable after an exception.
        let settlement = try bridge.settle([["A": 100, "B": -100]])
        #expect(settlement.transfers == [Engine.Transfer(from: "B", to: "A", amountCents: 100)])
    }

    @Test func scriptThatThrowsOnLoadFailsInit() {
        #expect(throws: EngineError.self) {
            _ = try EngineBridge(script: "throw new Error('broken bundle')")
        }
    }
}
