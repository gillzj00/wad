import Foundation
import SwiftData
import Testing
@testable import Wad

/// The snapshot of a stored round, scored by the real engines, and the events
/// a score change on it triggers.
@MainActor
struct GameSnapshotRoundTests {
    let container: ModelContainer
    let bridge: EngineBridge
    let round: Round
    let scorer: RoundScorer

    init() throws {
        container = try ModelContainer(for: Round.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        bridge = try EngineBridge()
        round = try RoundFixtures.threePlayerDraft().makeRound(using: bridge)
        container.mainContext.insert(round)
        try container.mainContext.save()
        scorer = RoundScorer(round: round)
    }

    func snapshot() throws -> GameSnapshot {
        GameSnapshot(round: round, status: try RoundStatus(round: round, bridge: bridge))
    }

    @Test func playersScoresAndAmountsComeFromTheRound() throws {
        try scorer.setGross(5, playerID: "sam", hole: 2)
        let snapshot = try snapshot()
        #expect(snapshot.players == [
            GameSnapshot.Player(id: "zach", name: "Zach"),
            GameSnapshot.Player(id: "sam", name: "Sam"),
            GameSnapshot.Player(id: "alex", name: "Alex"),
        ])
        #expect(snapshot.scores == [GameSnapshot.Score(playerID: "sam", hole: 2, par: 5, gross: 5)])
        #expect(snapshot.greenieAmountCents == 500)
        #expect(snapshot.skinWins.isEmpty)
        #expect(snapshot.wadMakes.isEmpty)
        #expect(snapshot.greenieWins.isEmpty)
        #expect(snapshot.wolfWins.isEmpty)
    }

    /// Zach gets a tick on hole 1, so three pars give him the skin, net.
    @Test func aSoleLowestNetScoreIsASkinWin() throws {
        try scorer.setGross(4, playerID: "zach", hole: 1)
        try scorer.setGross(4, playerID: "sam", hole: 1)
        let before = try snapshot()
        #expect(before.skinWins.isEmpty)

        try scorer.setGross(4, playerID: "alex", hole: 1)
        let after = try snapshot()
        #expect(after.skinWins == [GameSnapshot.SkinWin(hole: 1, winnerID: "zach", atStakeCents: 500)])
        let events = EventDetector.events(before: before, after: after)
        #expect(events.map(\.kind) == [.skinWon])
        #expect(events.first?.playerNames == ["Zach"])
        #expect(events.first?.amountCents == 500)
    }

    @Test func aWadMakeAndAGreenieAreInTheSnapshot() throws {
        let before = try snapshot()
        try scorer.addWadMaker(playerID: "sam", hole: 2)
        try scorer.setGross(3, playerID: "alex", hole: 3)
        try scorer.setGreenieWinner("alex", hole: 3)
        let after = try snapshot()
        #expect(after.wadMakes == [GameSnapshot.WadMake(hole: 2, playerID: "sam", valueCents: 700)])
        #expect(after.greenieWins == [GameSnapshot.GreenieWin(hole: 3, winnerID: "alex")])
        #expect(EventDetector.events(before: before, after: after).map(\.kind) == [.greenie, .wadTaken])
    }

    /// A four-player Wolf round: a hole the Wolf's side wins is a Wolf win
    /// (the Wolf first, then the partner), a hole the opponents win, a tied
    /// hole and a hole that needs a Wolf are not.
    @Test func aHoleWonByTheWolfsSideIsAWolfWin() throws {
        let wolfRound = try WolfRoundTests.wolfDraft().makeRound(using: bridge)
        container.mainContext.insert(wolfRound)
        let play = WolfRoundTests(container: container, bridge: bridge)
        func snapshot() throws -> GameSnapshot {
            GameSnapshot(round: wolfRound, status: try RoundStatus(round: wolfRound, bridge: bridge))
        }

        // Hole 1: Zach alone wins. Hole 2: Sam takes Jo and they win. Hole 3:
        // Alex alone loses to Zach's 2. Hole 4: Jo alone, tied.
        let before = try snapshot()
        #expect(before.wolfWins.isEmpty)
        try play.play(wolfRound, hole: 1, birdie: "zach")
        try play.play(wolfRound, hole: 2, birdie: "jo", choice: .partner("jo"))
        try play.play(wolfRound, hole: 3, birdie: "zach")
        try play.play(wolfRound, hole: 4)
        let after = try snapshot()
        #expect(after.wolfWins == [
            GameSnapshot.WolfWin(hole: 1, winnerIDs: ["zach"]),
            GameSnapshot.WolfWin(hole: 2, winnerIDs: ["sam", "jo"]),
        ])
        let events = EventDetector.events(before: before, after: after).filter { $0.kind == .wolfHoleWon }
        #expect(events.map(\.hole) == [1, 2])
        #expect(events.map(\.playerNames) == [["Zach"], ["Sam", "Jo"]])

        // Every other hole to 16 tied: Alex (0 against 5, 3, 3) is the Wolf on
        // 17 and wins alone, 4 points. Sam and Jo are then tied for last place:
        // hole 18 needs a Wolf and is no event, even with every score and the
        // choice in. Once the group picks Sam and Sam's birdie wins, it is.
        for hole in 5...16 { try play.play(wolfRound, hole: hole) }
        try play.play(wolfRound, hole: 17, birdie: "alex")
        let after17 = try snapshot()
        #expect(after17.wolfWins.last == GameSnapshot.WolfWin(hole: 17, winnerIDs: ["alex"]))

        try play.play(wolfRound, hole: 18, birdie: "sam")
        let needsWolf = try snapshot()
        #expect(try RoundStatus(round: wolfRound, bridge: bridge).wolfHole(18)?.status == .needsWolf)
        #expect(needsWolf.wolfWins.count == 3)
        #expect(EventDetector.events(before: after17, after: needsWolf).filter { $0.kind == .wolfHoleWon }.isEmpty)

        try RoundScorer(round: wolfRound).setWolf("sam", hole: 18)
        let picked = try snapshot()
        #expect(picked.wolfWins.last == GameSnapshot.WolfWin(hole: 18, winnerIDs: ["sam"]))
        #expect(EventDetector.events(before: needsWolf, after: picked).map(\.kind) == [.wolfHoleWon])
    }

    @Test func aRecordedGreenieWithoutAScoreIsNotAWinYet() throws {
        try scorer.setGross(3, playerID: "alex", hole: 3)
        try scorer.setGreenieWinner("alex", hole: 3)
        try scorer.setGross(nil, playerID: "alex", hole: 3)
        #expect(try snapshot().greenieWins.isEmpty)
    }

    @Test func withoutAnEngineOnlyTheScoresAreKnown() throws {
        try scorer.setGross(2, playerID: "zach", hole: 1)
        let snapshot = GameSnapshot(round: round, status: nil)
        #expect(snapshot.scores.count == 1)
        #expect(snapshot.events.map(\.kind) == [.eagle])
    }
}
