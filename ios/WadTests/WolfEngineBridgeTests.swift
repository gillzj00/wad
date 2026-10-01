import Foundation
import Testing
@testable import Wad

/// Wolf through the real engines.js bundle: the worked example of
/// docs/domain-model.md (Game 4), a tie for last place and the types that
/// cross the JavaScript boundary.
struct WolfEngineBridgeTests {
    static let course18 = EngineBridgeTests.course18
    static let order = ["A", "B", "C", "D"]
    static let players = EngineBridgeTests.players(order)

    let bridge: EngineBridge

    init() throws {
        bridge = try EngineBridge()
    }

    /// Every player makes par on the holes in `holes`, except where `gross` says otherwise.
    static func parScores(holes: ClosedRange<Int>, gross: [Int: [String: Int]] = [:]) -> [Engine.Score] {
        course18.filter { holes.contains($0.hole) }.flatMap { hole in
            order.map { Engine.Score(userId: $0, hole: hole.hole, gross: gross[hole.hole]?[$0] ?? hole.par) }
        }
    }

    static func event(_ hole: Int, _ wolf: Engine.WolfEvent) -> Engine.HoleEvents {
        Engine.HoleEvents(hole: hole, wolf: wolf)
    }

    static let lone = Engine.WolfEvent(choice: .lone)
    static func partner(_ id: String) -> Engine.WolfEvent { Engine.WolfEvent(choice: .partner, partnerUserId: id) }

    func input(
        players: [Engine.Player] = players,
        teeOrder: [String] = order,
        scores: [Engine.Score],
        events: [Engine.HoleEvents],
        pointCents: Int = 100
    ) -> Engine.WolfInput {
        Engine.WolfInput(
            players: players, teeOrder: teeOrder, holes: Self.course18, scores: scores, holeEvents: events, pointCents: pointCents
        )
    }

    /// Tee order A, B, C, D, $1 a point. Hole 1: Wolf A takes B and wins, 2
    /// each. Hole 2: Wolf B alone loses, 1 each to A, C, D. Hole 3: Wolf C takes
    /// D and they lose, 3 each to A and B. Hole 4: Wolf D alone wins, 4.
    /// Points A 6, B 5, C 1, D 5, 17 in total: A +$7, B +$3, C -$13, D +$3.
    @Test func domainModelExampleFourPlayers() throws {
        let scores = Self.parScores(holes: 1...4, gross: [1: ["A": 3], 2: ["B": 5, "C": 5, "D": 5, "A": 4], 3: ["A": 2], 4: ["D": 3]])
        let result = try #require(try bridge.scoreWolf(input(
            scores: scores,
            events: [Self.event(1, Self.partner("B")), Self.event(2, Self.lone), Self.event(3, Self.partner("D")), Self.event(4, Self.lone)]
        )))

        #expect(result.teeOrder == Self.order)
        #expect(result.holes.count == 18)
        #expect(result.holes[0] == Engine.WolfHoleResult(
            hole: 1, wolfUserId: "A", status: .wonByWolfSide, invalidReason: nil, choice: .partner, partnerUserId: "B",
            lastPlace: nil, wolfSide: ["A", "B"], opponents: ["C", "D"], wolfSideNet: 3, opponentsNet: 4,
            net: ["A": 3, "B": 4, "C": 4, "D": 4], points: ["A": 2, "B": 2, "C": 0, "D": 0]
        ))
        #expect(result.holes[1].status == .wonByOpponents)
        #expect(result.holes[1].points == ["A": 1, "B": 0, "C": 1, "D": 1])
        #expect(result.holes[2].status == .wonByOpponents)
        #expect(result.holes[2].points == ["A": 3, "B": 3, "C": 0, "D": 0])
        #expect(result.holes[3].status == .wonByWolfSide)
        #expect(result.holes[3].wolfSide == ["D"])
        #expect(result.holes[3].points == ["A": 0, "B": 0, "C": 0, "D": 4])
        #expect(result.holes[4].status == .pending)
        #expect(result.holes[4].wolfUserId == "A")
        #expect(result.holes[16].status == .pending)
        #expect(result.holes[16].wolfUserId == nil)
        #expect(result.points == ["A": 6, "B": 5, "C": 1, "D": 5])
        #expect(result.deltas == ["A": 700, "B": 300, "C": -1300, "D": 300])
        #expect(result.deltas.values.reduce(0, +) == 0)
        #expect(!result.complete)
    }

    /// A wins hole 1 alone; every other hole to 16 is tied, so B, C and D are
    /// tied for last place after 16. Hole 17 needs a Wolf and scores nothing
    /// until one of them is recorded.
    @Test func tieForLastPlaceNeedsARecordedWolf() throws {
        let scores = Self.parScores(holes: 1...17, gross: [1: ["A": 3], 17: ["B": 3]])
        var events = (1...17).map { Self.event($0, Self.lone) }
        let result = try #require(try bridge.scoreWolf(input(scores: scores, events: events)))

        let hole17 = result.holes[16]
        #expect(hole17.status == .needsWolf)
        #expect(hole17.wolfUserId == nil)
        #expect(hole17.lastPlace == ["B", "C", "D"])
        #expect(hole17.choice == .lone)
        #expect(hole17.points == ["A": 0, "B": 0, "C": 0, "D": 0])
        #expect(result.holes[17].status == .pending)
        #expect(result.holes[17].lastPlace == nil)
        #expect(result.points == ["A": 4, "B": 0, "C": 0, "D": 0])
        #expect(!result.complete)

        // The group records B, who is among those tied. B's 3 wins alone.
        events[16] = Self.event(17, Engine.WolfEvent(choice: .lone, wolfUserId: "B"))
        let recorded = try #require(try bridge.scoreWolf(input(scores: scores, events: events)))
        #expect(recorded.holes[16].status == .wonByWolfSide)
        #expect(recorded.holes[16].wolfUserId == "B")
        #expect(recorded.holes[16].lastPlace == ["B", "C", "D"])
        #expect(recorded.points == ["A": 4, "B": 4, "C": 0, "D": 0])
        // Hole 18: C and D are now tied for last and 18 has no record.
        #expect(recorded.holes[17].status == .needsWolf)
        #expect(recorded.holes[17].lastPlace == ["C", "D"])

        // A, who is not in last place, is refused.
        events[16] = Self.event(17, Engine.WolfEvent(choice: .lone, wolfUserId: "A"))
        let refused = try #require(try bridge.scoreWolf(input(scores: scores, events: events)))
        #expect(refused.holes[16].status == .invalid)
        #expect(refused.holes[16].invalidReason == .wolfNotInLastPlace)
        #expect(refused.points == ["A": 4, "B": 0, "C": 0, "D": 0])
    }

    @Test func invalidRecordsAreReportedAndScoreNothing() throws {
        let scores = Self.parScores(holes: 1...1, gross: [1: ["A": 3]])
        let result = try #require(try bridge.scoreWolf(input(scores: scores, events: [Self.event(1, Self.partner("A"))])))
        #expect(result.holes[0].status == .invalid)
        #expect(result.holes[0].invalidReason == .partnerIsWolf)
        #expect(result.holes[0].wolfUserId == "A")
        #expect(result.deltas == ["A": 0, "B": 0, "C": 0, "D": 0])
    }

    @Test func pointValueScalesTheDeltas() throws {
        let scores = Self.parScores(holes: 1...1, gross: [1: ["A": 3]])
        let result = try #require(try bridge.scoreWolf(input(scores: scores, events: [Self.event(1, Self.lone)], pointCents: 250)))
        // A has 4 points of 4: 250 * (16 - 4) and 250 * (0 - 4).
        #expect(result.deltas == ["A": 3000, "B": -1000, "C": -1000, "D": -1000])
    }

    @Test func unavailableWithoutExactlyFourPlayers() throws {
        let three = Array(Self.players.prefix(3))
        #expect(try bridge.scoreWolf(input(players: three, teeOrder: ["A", "B", "C"], scores: [], events: [])) == nil)
        #expect(try bridge.scoreWolf(input(teeOrder: ["A", "B", "C", "C"], scores: [], events: [])) == nil)
    }

    @Test func rotationFollowsTheTeeOrderGiven() throws {
        let result = try #require(try bridge.scoreWolf(input(teeOrder: ["C", "A", "D", "B"], scores: [], events: [])))
        #expect(result.teeOrder == ["C", "A", "D", "B"])
        #expect(result.holes.prefix(5).map(\.wolfUserId) == ["C", "A", "D", "B", "C"])
        #expect(result.holes.allSatisfy { $0.status == .pending })
    }

    // MARK: Types

    @Test func holeEventsEncodeTheWolfRecordOnlyWhenThereIsOne() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let without = String(decoding: try encoder.encode(Engine.HoleEvents(hole: 3, wadMakers: ["A"])), as: UTF8.self)
        #expect(without == #"{"greenieWinner":null,"hole":3,"wadMakers":["A"]}"#)

        let with = String(decoding: try encoder.encode(Engine.HoleEvents(
            hole: 17, wolf: Engine.WolfEvent(choice: .partner, partnerUserId: "B", wolfUserId: "C")
        )), as: UTF8.self)
        #expect(with == #"{"greenieWinner":null,"hole":17,"wadMakers":[],"wolf":{"choice":"partner","partnerUserId":"B","wolfUserId":"C"}}"#)

        let lone = String(decoding: try encoder.encode(Engine.WolfEvent(choice: .lone)), as: UTF8.self)
        #expect(lone == #"{"choice":"lone"}"#)
    }

    @Test func holeResultDecodesTheEngineShape() throws {
        let json = """
        {"hole":18,"wolfUserId":null,"status":"needs_wolf","invalidReason":null,"choice":"partner","partnerUserId":"A",
         "lastPlace":["B","C"],"wolfSide":null,"opponents":null,"wolfSideNet":null,"opponentsNet":null,
         "net":{"A":4,"B":4,"C":5,"D":5},"points":{"A":0,"B":0,"C":0,"D":0}}
        """
        let result = try JSONDecoder().decode(Engine.WolfHoleResult.self, from: Data(json.utf8))
        #expect(result == Engine.WolfHoleResult(
            hole: 18, wolfUserId: nil, status: .needsWolf, invalidReason: nil, choice: .partner, partnerUserId: "A",
            lastPlace: ["B", "C"], wolfSide: nil, opponents: nil, wolfSideNet: nil, opponentsNet: nil,
            net: ["A": 4, "B": 4, "C": 5, "D": 5], points: ["A": 0, "B": 0, "C": 0, "D": 0]
        ))
        let reencoded = try JSONDecoder().decode(Engine.WolfHoleResult.self, from: try JSONEncoder().encode(result))
        #expect(reencoded == result)
    }
}
