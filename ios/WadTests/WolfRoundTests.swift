import Foundation
import SwiftData
import Testing
@testable import Wad

/// Wolf during a round, through the real engine bundle: the tee order and its
/// lock, who the Wolf is on each hole, the tie prompt on 17 and 18, and the
/// group's choice with its corrections.
@MainActor
struct WolfRoundTests {
    let container: ModelContainer
    let bridge: EngineBridge

    init() throws {
        self.init(
            container: try ModelContainer(for: Round.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)),
            bridge: try EngineBridge()
        )
    }

    /// For the other suites that play Wolf holes with `play`.
    init(container: ModelContainer, bridge: EngineBridge) {
        self.container = container
        self.bridge = bridge
    }

    /// Zach, Sam, Alex and Jo with the same handicap (no ticks), Wolf on at $1 a
    /// point, holes unscored. Pars 4 5 3 4 4 3 5 4 4 / 4 3 5 4 4 5 3 4 4.
    static func wolfDraft() -> RoundDraft {
        var draft = RoundFixtures.fourPlayerDraft()
        for offset in draft.players.indices { draft.players[offset].courseHandicapText = "7" }
        draft.wolf.isEnabled = true
        return draft
    }

    func makeRound(_ draft: RoundDraft = wolfDraft()) throws -> Round {
        let round = try draft.makeRound(using: bridge)
        container.mainContext.insert(round)
        return round
    }

    /// Scores the hole: par for everyone but `birdie`, who makes one under, and
    /// records the choice (and the Wolf, when given).
    func play(_ round: Round, hole: Int, birdie: String? = nil, choice: WolfChoiceRecord? = .lone, wolf: String? = nil) throws {
        let scorer = RoundScorer(round: round)
        let par = try #require(round.hole(hole)).par
        for player in round.orderedPlayers {
            try scorer.setGross(player.playerID == birdie ? par - 1 : par, playerID: player.playerID, hole: hole)
        }
        try scorer.setWolfChoice(choice, hole: hole)
        if let wolf { try scorer.setWolf(wolf, hole: hole) }
    }

    func status(_ round: Round) throws -> RoundStatus {
        try RoundStatus(round: round, bridge: bridge)
    }

    func model(_ round: Round, hole: Int) throws -> WolfHoleModel {
        let status = try status(round)
        return WolfHoleModel(
            result: try #require(status.wolfHole(hole)),
            game: try #require(status.wolf),
            recordedWolfID: round.hole(hole)?.wolfPlayerID,
            name: { id in round.players.first { $0.playerID == id }?.displayName ?? id }
        )
    }

    // MARK: Tee order

    @Test func teeOrderCanChangeUntilTheFirstScoreOrWolfRecord() throws {
        let round = try makeRound()
        let scorer = RoundScorer(round: round)
        #expect(round.isWolfTeeOrderLocked == false)
        #expect(round.wolfTeeOrder == ["zach", "sam", "alex", "jo"])

        try scorer.moveWolfTeeOrder("jo", by: -1)
        #expect(round.wolfTeeOrder == ["zach", "sam", "jo", "alex"])
        try scorer.setWolfTeeOrder(["alex", "jo", "sam", "zach"])
        #expect(round.wolfTeeOrder == ["alex", "jo", "sam", "zach"])
        #expect(throws: WolfScoringError.teeOrderNotThePlayers) { try scorer.setWolfTeeOrder(["alex", "jo", "sam"]) }
        #expect(throws: WolfScoringError.teeOrderNotThePlayers) { try scorer.setWolfTeeOrder(["alex", "jo", "sam", "sam"]) }
        #expect(throws: WolfScoringError.teeOrderNotThePlayers) { try scorer.setWolfTeeOrder(["alex", "jo", "sam", "pat"]) }

        // The first score locks it.
        try scorer.setGross(4, playerID: "zach", hole: 1)
        #expect(round.isWolfTeeOrderLocked)
        #expect(throws: WolfScoringError.teeOrderLocked) { try scorer.moveWolfTeeOrder("zach", by: -1) }
        #expect(round.wolfTeeOrder == ["alex", "jo", "sam", "zach"])

        // Clearing the score unlocks it again; a Wolf record locks it too.
        try scorer.setGross(nil, playerID: "zach", hole: 1)
        #expect(round.isWolfTeeOrderLocked == false)
        try scorer.setWolfChoice(.lone, hole: 1)
        #expect(round.isWolfTeeOrderLocked)
        #expect(throws: WolfScoringError.teeOrderLocked) { try scorer.setWolfTeeOrder(["zach", "sam", "alex", "jo"]) }
    }

    @Test func aFullyScoredRoundIsLocked() throws {
        let round = try makeRound()
        RoundFixtures.scoreEveryHoleAtPar(round)
        #expect(round.isWolfTeeOrderLocked)
    }

    @Test func teeOrderNeedsWolf() throws {
        let round = try makeRound(RoundFixtures.fourPlayerDraft())
        #expect(throws: WolfScoringError.notPlayed) { try RoundScorer(round: round).setWolfTeeOrder(["zach", "sam", "alex", "jo"]) }
    }

    // MARK: Who the Wolf is

    @Test func wolfRotatesThroughTheTeeOrderOnHolesOneToSixteen() throws {
        let round = try makeRound()
        try RoundScorer(round: round).setWolfTeeOrder(["sam", "zach", "jo", "alex"])
        let game = try #require(try status(round).wolf)

        #expect(game.teeOrder == ["sam", "zach", "jo", "alex"])
        #expect(game.holes.prefix(16).map(\.wolfUserId) == Array(repeating: ["sam", "zach", "jo", "alex"], count: 4).flatMap { $0 })
        #expect(game.holes[16].wolfUserId == nil)
        #expect(game.holes[17].wolfUserId == nil)
        #expect(game.holes.allSatisfy { $0.status == .pending })

        let first = try model(round, hole: 1)
        #expect(first.wolf == WolfHoleModel.Player(playerID: "sam", name: "Sam"))
        #expect(first.partnerCandidates.map(\.name) == ["Zach", "Jo", "Alex"])
        #expect(first.tiedForLast.isEmpty)
        #expect(first.canChoose)
        #expect(first.line == StatusLine(title: "Sam is the Wolf", detail: "Choose a partner or go Lone Wolf."))

        let last = try model(round, hole: 17)
        #expect(last.wolf == nil)
        #expect(last.canChoose == false)
        #expect(last.line == StatusLine(
            title: "Waiting for earlier holes",
            detail: "The Wolf is the player in last place on points once every earlier hole is scored."
        ))
    }

    /// Hole 1: Zach alone makes 3 (Zach 4). Hole 2: Sam alone makes 4 on the par 5
    /// (Sam 4). Hole 3: Alex alone makes 2 on the par 3 (Alex 4). Every other hole
    /// to 16 is tied, so Jo is last alone after 16 and is the Wolf on 17 without
    /// anyone recording it. Jo alone makes 3 on 17: all four have 4, and hole 18
    /// needs a Wolf among all of them.
    @Test func wolfOnSeventeenAndEighteenIsThePlayerInLastPlace() throws {
        let round = try makeRound()
        for hole in 1...16 {
            try play(round, hole: hole, birdie: ["zach", "sam", "alex"][safe: hole - 1])
        }
        var game = try #require(try status(round).wolf)
        #expect(game.points == ["zach": 4, "sam": 4, "alex": 4, "jo": 0])
        #expect(game.holes[16].wolfUserId == "jo")
        #expect(game.holes[16].lastPlace == ["jo"])
        #expect(game.holes[16].status == .pending)
        let seventeen = try model(round, hole: 17)
        #expect(seventeen.wolf?.name == "Jo")
        #expect(seventeen.tiedForLast.isEmpty)
        #expect(seventeen.partnerCandidates.map(\.name) == ["Zach", "Sam", "Alex"])
        #expect(seventeen.standings.map(\.points) == [4, 4, 4, 0])
        #expect(seventeen.standings.map(\.isLast) == [false, false, false, true])
        #expect(seventeen.standings.map(\.isFirst) == [true, true, true, false])

        try play(round, hole: 17, birdie: "jo")
        game = try #require(try status(round).wolf)
        #expect(game.holes[16].status == .wonByWolfSide)
        #expect(game.points == ["zach": 4, "sam": 4, "alex": 4, "jo": 4])
        #expect(game.holes[17].status == .needsWolf)
        #expect(game.holes[17].lastPlace == ["zach", "sam", "alex", "jo"])
        #expect(try model(round, hole: 18).tiedForLast.map(\.name) == ["Zach", "Sam", "Alex", "Jo"])
    }

    // MARK: Open Question 4: the tie prompt

    /// Zach alone wins hole 1; every other hole to 16 is tied. Sam, Alex and Jo
    /// are tied for last place, so hole 17 needs a Wolf: the engine does not
    /// pick, the group does, among those three only.
    @Test func tieForLastPlaceAsksTheGroupToPickTheWolf() throws {
        let round = try makeRound()
        for hole in 1...16 { try play(round, hole: hole, birdie: hole == 1 ? "zach" : nil) }
        try play(round, hole: 17)

        var model = try model(round, hole: 17)
        #expect(model.needsWolf)
        #expect(model.wolf == nil)
        #expect(model.canChoose == false)
        #expect(model.recordedWolfID == nil)
        #expect(model.tiedForLast.map(\.name) == ["Sam", "Alex", "Jo"])
        #expect(model.line == StatusLine(
            title: "Needs a Wolf",
            detail: "Sam, Alex and Jo are tied for last place. Pick the Wolf among them; the hole scores nothing until then.",
            isWarning: true
        ))
        #expect(model.result.points.values.allSatisfy { $0 == 0 })
        #expect(try status(round).flaggedWolfHoles == [17])
        #expect(try status(round).wolf?.points == ["zach": 4, "sam": 0, "alex": 0, "jo": 0])

        // The group picks Sam: the hole is scored (tied, everyone made par).
        try RoundScorer(round: round).setWolf("sam", hole: 17)
        model = try self.model(round, hole: 17)
        #expect(model.needsWolf == false)
        #expect(model.wolf?.name == "Sam")
        #expect(model.recordedWolfID == "sam")
        #expect(model.tiedForLast.map(\.name) == ["Sam", "Alex", "Jo"])
        #expect(model.partnerCandidates.map(\.name) == ["Zach", "Alex", "Jo"])
        #expect(model.result.status == .tied)
        #expect(model.line == StatusLine(title: "Tied, no points", detail: "Lone Wolf Sam 4 against 4. Nothing carries over."))
        // Still tied for last after the tied hole: 18 needs a Wolf now.
        #expect(try status(round).flaggedWolfHoles == [18])
        #expect(try self.model(round, hole: 18).tiedForLast.map(\.name) == ["Sam", "Alex", "Jo"])

        // Zach is not in last place: refused, the hole scores nothing, and the record can be cleared.
        try RoundScorer(round: round).setWolf("zach", hole: 17)
        model = try self.model(round, hole: 17)
        #expect(model.result.status == .invalid)
        #expect(model.result.invalidReason == .wolfNotInLastPlace)
        #expect(model.hasRefusedWolf)
        #expect(model.line == StatusLine(
            title: "Not scored: the recorded Wolf is not in last place (Sam, Alex and Jo are)",
            detail: "Correct the record. The hole scores no points until then.",
            isWarning: true
        ))
        #expect(try status(round).flaggedWolfHoles == [17])
        try RoundScorer(round: round).setWolf(nil, hole: 17)
        #expect(try self.model(round, hole: 17).needsWolf)
    }

    @Test func seededWolfRoundWaitsForTheGroupOnSeventeen() throws {
        let round = try DebugRounds.wolf(using: bridge)
        container.mainContext.insert(round)
        #expect(round.playsWolf)
        #expect(round.wolfPointCents == 100)
        #expect(round.completedHoles == Array(1...16))
        let game = try #require(try status(round).wolf)
        #expect(game.points == ["zach": 5, "sam": 5, "alex": 5, "jo": 8])
        #expect(game.holes[16].status == .needsWolf)
        #expect(game.holes[16].lastPlace == ["zach", "sam", "alex"])
        #expect(game.holes.prefix(16).allSatisfy { $0.status != .pending && $0.status != .invalid })
    }

    // MARK: The choice

    @Test func choiceIsRecordedAndCanBeCorrected() throws {
        let round = try makeRound()
        let scorer = RoundScorer(round: round)
        try play(round, hole: 1, birdie: "zach", choice: .partner("sam"))
        let hole = try #require(round.hole(1))
        #expect(hole.wolfChoice == "partner")
        #expect(hole.wolfPartnerID == "sam")
        #expect(hole.wolfPlayerID == nil)
        #expect(hole.wolfEvent == Engine.WolfEvent(choice: .partner, partnerUserId: "sam", wolfUserId: nil))
        #expect(round.engineHoleEvents == [Engine.HoleEvents(hole: 1, wolf: hole.wolfEvent)])

        var model = try model(round, hole: 1)
        #expect(model.isPartner("sam"))
        #expect(model.isLone == false)
        #expect(model.result.status == .wonByWolfSide)
        #expect(model.result.points == ["zach": 2, "sam": 2, "alex": 0, "jo": 0])
        #expect(model.line == StatusLine(title: "Zach and Sam win 2 points each", detail: "Net best ball 3 against 4."))

        // Corrected to Lone Wolf: 4 points.
        try scorer.setWolfChoice(.lone, hole: 1)
        #expect(hole.wolfChoice == "lone")
        #expect(hole.wolfPartnerID == nil)
        model = try self.model(round, hole: 1)
        #expect(model.isLone)
        #expect(model.result.points == ["zach": 4, "sam": 0, "alex": 0, "jo": 0])
        #expect(model.line == StatusLine(title: "Lone Wolf Zach wins 4 points", detail: "Net best ball 3 against 4."))

        // Cleared: pending, and no points.
        try scorer.setWolfChoice(nil, hole: 1)
        #expect(hole.wolfEvent == nil)
        #expect(round.engineHoleEvents.isEmpty)
        model = try self.model(round, hole: 1)
        #expect(model.result.status == .pending)
        #expect(model.line.title == "Zach is the Wolf")
        #expect(try status(round).wolf?.points == ["zach": 0, "sam": 0, "alex": 0, "jo": 0])

        // A partner who is the Wolf is refused by the engine, never corrected silently.
        try scorer.setWolfChoice(.partner("zach"), hole: 1)
        model = try self.model(round, hole: 1)
        #expect(model.result.status == .invalid)
        #expect(model.result.invalidReason == .partnerIsWolf)
        #expect(model.hasRefusedWolf == false)
        #expect(model.line.title == "Not scored: the partner is the Wolf")
        #expect(try status(round).flaggedWolfHoles == [1])

        #expect(throws: ScoringError.unknownPlayer("pat")) { try scorer.setWolfChoice(.partner("pat"), hole: 1) }
        #expect(throws: ScoringError.unknownHole(19)) { try scorer.setWolfChoice(.lone, hole: 19) }
        #expect(throws: ScoringError.unknownPlayer("pat")) { try scorer.setWolf("pat", hole: 17) }
    }

    @Test func recordsArePersisted() throws {
        let round = try makeRound()
        try play(round, hole: 2, birdie: "sam", choice: .partner("jo"))
        try RoundScorer(round: round).setWolf("sam", hole: 17)
        try RoundScorer(round: round).setWolfChoice(.lone, hole: 17)

        let reread = try #require(try ModelContext(container).fetch(FetchDescriptor<Round>()).first)
        #expect(reread.wolfPointCents == 100)
        #expect(reread.wolfTeeOrderIDs == ["zach", "sam", "alex", "jo"])
        #expect(reread.hole(2)?.wolfEvent == Engine.WolfEvent(choice: .partner, partnerUserId: "jo"))
        #expect(reread.hole(17)?.wolfEvent == Engine.WolfEvent(choice: .lone, wolfUserId: "sam"))
        #expect(reread.hole(3)?.wolfEvent == nil)
    }

    @Test func summaryKeyChangesWithTheWolfRecord() throws {
        let round = try makeRound()
        let before = RoundSummaryKey(round: round)
        try RoundScorer(round: round).setWolfChoice(.lone, hole: 1)
        #expect(RoundSummaryKey(round: round) != before)
        #expect(RoundSummaryKey(round: round).wolf?.holeEvents == [Engine.HoleEvents(hole: 1, wolf: Engine.WolfEvent(choice: .lone))])
    }

    // MARK: Wording

    @Test func wordsTheHoleResults() throws {
        let round = try makeRound()
        let name = { (id: String) in round.players.first { $0.playerID == id }?.displayName ?? id }
        // Hole 1: Zach alone loses to Sam's 3. Hole 2: Sam takes Jo and they lose to Alex's 4.
        try play(round, hole: 1, birdie: "sam")
        try play(round, hole: 2, birdie: "alex", choice: .partner("jo"))
        try play(round, hole: 3, choice: .partner("zach"))
        try play(round, hole: 4, birdie: "jo", choice: nil)
        let game = try #require(try status(round).wolf)

        #expect(WolfText.hole(game.holes[0], name: name) == StatusLine(
            title: "Lone Wolf Zach loses: 1 point to each of Sam, Alex and Jo",
            detail: "Lone Wolf Zach lost the net best ball 4 to 3."
        ))
        #expect(WolfText.hole(game.holes[1], name: name) == StatusLine(
            title: "Zach and Alex win 3 points each",
            detail: "Sam and Jo lost the net best ball 5 to 4."
        ))
        #expect(WolfText.hole(game.holes[2], name: name) == StatusLine(
            title: "Tied, no points",
            detail: "Alex and Zach 3 against 3. Nothing carries over."
        ))
        #expect(WolfText.hole(game.holes[3], name: name) == StatusLine(title: "Jo is the Wolf", detail: "Choose a partner or go Lone Wolf."))
        // Zach lost hole 1 (Sam, Alex, Jo +1) and won hole 2 with Alex (+3 each).
        #expect(game.points == ["zach": 3, "sam": 1, "alex": 4, "jo": 1])

        #expect(WolfText.standings(game.points, order: game.teeOrder, name: name) == "Zach 3, Sam 1, Alex 4, Jo 1")
        #expect(WolfText.teeOrder(game.teeOrder, name: name) == "Zach, Sam, Alex, Jo")
        #expect(WolfText.list(["zach"], name: name) == "Zach")
        #expect(WolfText.list(["zach", "sam"], name: name) == "Zach and Sam")
        #expect(WolfText.list([], name: name) == "-")
        #expect(WolfText.points(1) == "1 point")
        #expect(WolfText.points(3) == "3 points")
        #expect(WolfText.result(points: 6, cents: 700) == "6 points, +$7.00")
        #expect(WolfText.pointValue(100) == "$1.00 a point. Every pair of players settles the difference in their points.")
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
