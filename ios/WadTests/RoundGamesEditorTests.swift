import Foundation
import SwiftData
import Testing
@testable import Wad

/// Changing who is in each game and the skins carryover after the setup:
/// what is removed, what is saved, how the settlement follows, and that no
/// show comes of it.
@MainActor
struct RoundGamesEditorTests {
    let container: ModelContainer
    let bridge: EngineBridge
    let round: Round
    let scorer: RoundScorer
    let editor: RoundGamesEditor

    /// Four players: Zach (15), Sam (7), Alex (10), Jo (7). Holes 3 and 6 are par 3s.
    init() throws {
        container = try ModelContainer(for: Round.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        bridge = try EngineBridge()
        round = try RoundFixtures.fourPlayerDraft().makeRound(using: bridge)
        container.mainContext.insert(round)
        try container.mainContext.save()
        scorer = RoundScorer(round: round)
        editor = RoundGamesEditor(round: round)
    }

    func games(_ change: (inout RoundGames) -> Void) -> RoundGames {
        var games = RoundGames(round: round)
        change(&games)
        return games
    }

    func out(_ playerID: String, of game: SideGame) -> RoundGames {
        games { games in
            let index = games.players.firstIndex { $0.id == playerID }!
            games.players[index].setPlays(game, false)
        }
    }

    func storedRound() throws -> Round {
        try #require(try ModelContext(container).fetch(FetchDescriptor<Round>()).first)
    }

    func settlement() throws -> RoundSettlement {
        try RoundSettlement(round: round, bridge: bridge)
    }

    func result(_ playerID: String) throws -> RoundSettlement.PlayerResult {
        try #require(try settlement().players.first { $0.playerID == playerID })
    }

    /// Par for everyone on the par 3s, Jo's greenie on 3, Sam's on 6, and Wad
    /// makes: Sam, Jo, Zach on 4 and Jo on 12.
    func recordEvents() throws {
        for hole in [3, 6] {
            try scorer.setParForUnscored(hole: hole)
        }
        try scorer.setGreenieWinner("jo", hole: 3)
        try scorer.setGreenieWinner("sam", hole: 6)
        for maker in ["sam", "jo", "zach"] {
            try scorer.addWadMaker(playerID: maker, hole: 4)
        }
        try scorer.addWadMaker(playerID: "jo", hole: 12)
    }

    // MARK: Removals

    @Test func leavingGreeniesClearsOnlyThatPlayersGreenies() throws {
        try recordEvents()
        try editor.apply(out("jo", of: .greenies))

        #expect(round.hole(3)?.greenieWinnerID == nil)
        #expect(round.hole(6)?.greenieWinnerID == "sam")
        #expect(round.hole(4)?.wadMakerIDs == ["sam", "jo", "zach"])
        #expect(round.hole(12)?.wadMakerIDs == ["jo"])
        #expect(round.players(in: .greenies).map(\.playerID) == ["zach", "sam", "alex"])
    }

    @Test func leavingWadRemovesOnlyThatPlayersMakesInOrder() throws {
        try recordEvents()
        try editor.apply(out("jo", of: .wad))

        #expect(round.hole(4)?.wadMakerIDs == ["sam", "zach"])
        #expect(round.hole(12)?.wadMakerIDs == [])
        #expect(round.hole(3)?.greenieWinnerID == "jo")
        #expect(round.players(in: .wad).map(\.playerID) == ["zach", "sam", "alex"])
    }

    @Test func leavingSkinsRemovesNothing() throws {
        try recordEvents()
        let games = out("jo", of: .skins)
        #expect(editor.removals(for: games).isEmpty)
        try editor.apply(games)

        #expect(round.hole(3)?.greenieWinnerID == "jo")
        #expect(round.hole(4)?.wadMakerIDs == ["sam", "jo", "zach"])
        #expect(round.hole(12)?.wadMakerIDs == ["jo"])
        #expect(round.players(in: .skins).map(\.playerID) == ["zach", "sam", "alex"])
    }

    @Test func removalsNameThePlayerAndTheHoles() throws {
        try recordEvents()
        let games = games { games in
            games.players[3].playsGreenies = false
            games.players[3].playsWad = false
            games.players[0].playsWad = false
        }
        let removals = editor.removals(for: games)
        #expect(removals == [
            GamesRemoval(playerID: "zach", name: "Zach", greenieHoles: [], wadHoles: [4]),
            GamesRemoval(playerID: "jo", name: "Jo", greenieHoles: [3], wadHoles: [4, 12]),
        ])
        #expect(removals.map(\.sentence) == [
            "Zach's Wad make on hole 4 will be removed.",
            "Jo's greenie on hole 3 and Wad makes on holes 4 and 12 will be removed.",
        ])
        #expect(GamesRemoval.holes([3, 6, 16]) == "holes 3, 6 and 16")
        #expect(GamesRemoval(playerID: "sam", name: "Sam", greenieHoles: [3, 6], wadHoles: []).sentence
            == "Sam's greenies on holes 3 and 6 will be removed.")
    }

    @Test func nothingToRemoveWhenThePlayerHasNothingInTheGame() throws {
        try recordEvents()
        #expect(editor.removals(for: out("alex", of: .wad)).isEmpty)
        #expect(editor.removals(for: out("alex", of: .greenies)).isEmpty)
        #expect(editor.removals(for: RoundGames(round: round)).isEmpty)
    }

    @Test func puttingAPlayerBackRestoresNothing() throws {
        try recordEvents()
        try editor.apply(out("jo", of: .greenies))
        try editor.apply(games { $0.players[3].playsGreenies = true })

        #expect(round.players(in: .greenies).count == 4)
        #expect(round.hole(3)?.greenieWinnerID == nil)
    }

    @Test func theEditIsSavedInTheStore() throws {
        try recordEvents()
        try editor.apply(games { games in
            games.players[3].playsWad = false
            games.skinsCarryover = false
        })

        let stored = try storedRound()
        #expect(stored.skinsCarryover == false)
        #expect(stored.players(in: .wad).map(\.playerID) == ["zach", "sam", "alex"])
        #expect(stored.hole(4)?.wadMakerIDs == ["sam", "zach"])
        #expect(stored.hole(12)?.wadMakerIDs == [])
    }

    // MARK: Carryover

    /// Hole 1 (stroke index 7): par for all, Zach's tick wins it, $5 from each.
    /// Hole 2 (index 11): par for all, no ticks, pushed.
    /// Hole 3 (index 17): Sam birdies and wins it: $10 from each with the
    /// carryover, $5 without. Sam: -5 + 30 = +25, or -5 + 15 = +10.
    @Test func changingTheCarryoverRescoresTheSkins() throws {
        for hole in 1...3 {
            try scorer.setParForUnscored(hole: hole)
        }
        try scorer.setGross(2, playerID: "sam", hole: 3)
        #expect(try result("sam").skinsCents == 2500)

        try editor.apply(games { $0.skinsCarryover = false })
        #expect(round.skinsCarryover == false)
        #expect(try settlement().skinsCarryover == false)
        #expect(try result("sam").skinsCents == 1000)
        #expect(try result("zach").skinsCents == 1000)

        try editor.apply(games { $0.skinsCarryover = true })
        #expect(try result("sam").skinsCents == 2500)
    }

    // MARK: Settlement

    /// $5 greenies. Jo wins 3 and Sam wins 6 among four: each +15 - 5 = +10,
    /// Zach and Alex -10. Jo out: Sam +10 from Zach and Alex, Jo 0. Jo back
    /// in, without the greenie: Sam +15, the others -5 each.
    @Test func theSettlementFollowsTheField() throws {
        try recordEvents()
        #expect(try result("jo").greeniesCents == 1000)
        #expect(try result("sam").greeniesCents == 1000)
        #expect(try result("zach").greeniesCents == -1000)

        try editor.apply(out("jo", of: .greenies))
        #expect(try result("jo").greeniesCents == 0)
        #expect(try result("jo").plays(.greenies) == false)
        #expect(try result("sam").greeniesCents == 1000)
        #expect(try result("zach").greeniesCents == -500)
        #expect(try result("alex").greeniesCents == -500)

        try editor.apply(games { $0.players[3].playsGreenies = true })
        #expect(try result("jo").greeniesCents == -500)
        #expect(try result("sam").greeniesCents == 1500)
        #expect(try result("zach").greeniesCents == -500)
        #expect(try result("alex").greeniesCents == -500)
    }

    @Test func aGameLeftWithOnePlayerIsNotPlayed() throws {
        try recordEvents()
        try editor.apply(games { games in
            for index in 1..<4 { games.players[index].playsGreenies = false }
        })
        #expect(!round.isPlayed(.greenies))
        #expect(round.hole(6)?.greenieWinnerID == nil)
        #expect(try settlement().players.allSatisfy { $0.greeniesCents == 0 })
    }

    // MARK: No shows

    /// Removing a greenie and Wad makes leaves nothing new to show.
    @Test func leavingGamesTriggersNoEvents() throws {
        try recordEvents()
        let before = GameSnapshot(round: round, status: try RoundStatus(round: round, bridge: bridge))
        try editor.apply(games { games in
            games.players[3].playsGreenies = false
            games.players[3].playsWad = false
            games.skinsCarryover = false
        })
        let after = GameSnapshot(round: round, status: try RoundStatus(round: round, bridge: bridge))
        #expect(EventDetector.events(before: before, after: after).isEmpty)
    }

    /// An edit can make a skin out of a push: Sam and Jo tie on hole 1 (Zach
    /// nets 5 with his tick, Alex 5) and Jo leaves Skins. The editor never goes through `EventCenter`, and the
    /// scoring screen takes its "before" right before each score change, so
    /// the next score change compares against the edited round and shows only
    /// what that score did, never the skin the edit made.
    @Test func theNextScoreChangeDoesNotShowWhatAnEditChanged() throws {
        let gross = ["zach": 6, "sam": 4, "alex": 5, "jo": 4]
        for (playerID, value) in gross {
            try scorer.setGross(value, playerID: playerID, hole: 1)
        }
        let beforeEdit = GameSnapshot(round: round, status: try RoundStatus(round: round, bridge: bridge))
        #expect(beforeEdit.skinWins.isEmpty)

        try editor.apply(out("jo", of: .skins))
        let afterEdit = GameSnapshot(round: round, status: try RoundStatus(round: round, bridge: bridge))
        #expect(afterEdit.skinWins.map(\.winnerID) == ["sam"])

        try scorer.setGross(4, playerID: "zach", hole: 5)
        let afterScore = GameSnapshot(round: round, status: try RoundStatus(round: round, bridge: bridge))
        #expect(EventDetector.events(before: afterEdit, after: afterScore).isEmpty)
    }
}
