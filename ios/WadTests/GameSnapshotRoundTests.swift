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
