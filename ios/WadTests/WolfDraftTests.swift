import Foundation
import Testing
@testable import Wad

/// Wolf in the setup flow: the toggle needs exactly four players, the point
/// value is money, and the tee order defaults to the order the players were
/// added and can be reordered.
struct WolfDraftTests {
    let bridge: EngineBridge

    init() throws {
        bridge = try EngineBridge()
    }

    @Test func offByDefaultWithADollarAPoint() {
        let draft = RoundDraft()
        #expect(draft.wolf.isEnabled == false)
        #expect(draft.wolf.pointText == "1.00")
        #expect(draft.wolf.pointCents == 100)
        #expect(draft.gameIssues().isEmpty)
    }

    @Test func offWolfIsNotValidatedAndNotStored() throws {
        var draft = RoundFixtures.unratedDraft()
        draft.wolf.pointText = "x"
        #expect(draft.gameIssues().isEmpty)

        let round = try draft.makeRound(using: bridge)
        #expect(round.playsWolf == false)
        #expect(round.wolfPointCents == nil)
        #expect(round.wolfTeeOrderIDs.isEmpty)
        #expect(round.wolfInput == nil)
    }

    @Test func needsExactlyFourPlayers() {
        #expect(WolfDraft.canBePlayed(playerCount: 4))
        #expect(!WolfDraft.canBePlayed(playerCount: 3))
        #expect(!WolfDraft.canBePlayed(playerCount: 2))

        var draft = RoundFixtures.threePlayerDraft()
        draft.wolf.isEnabled = true
        #expect(draft.gameIssues() == [.wolfNeedsFourPlayers])
        #expect(SetupIssue.wolfNeedsFourPlayers.message == "Wolf is played with exactly 4 players. Add players or turn Wolf off.")
        #expect(throws: SetupError.invalid([.wolfNeedsFourPlayers])) { try draft.makeRound(using: bridge) }

        draft.players.append(RoundDraft.Player(id: "jo", name: "Jo", courseHandicapText: "7"))
        #expect(draft.gameIssues().isEmpty)

        // A player removed after Wolf was turned on.
        draft.players.removeLast()
        #expect(draft.gameIssues() == [.wolfNeedsFourPlayers])
    }

    @Test func pointValueIsMoney() {
        var draft = RoundFixtures.fourPlayerDraft()
        draft.wolf.isEnabled = true
        for text in ["", "abc", "1.234", "-1"] {
            draft.wolf.pointText = text
            #expect(draft.gameIssues() == [.amountInvalid(game: "Wolf")], "\(text)")
            #expect(draft.wolf.pointCents == nil)
        }
        draft.wolf.pointText = "2.50"
        #expect(draft.gameIssues().isEmpty)
        #expect(draft.wolf.pointCents == 250)
        // Both issues at once, in the order players then amount.
        draft.players.removeLast()
        draft.wolf.pointText = "x"
        #expect(draft.gameIssues() == [.wolfNeedsFourPlayers, .amountInvalid(game: "Wolf")])
    }

    @Test func teeOrderDefaultsToTheOrderPlayersWereAdded() {
        let draft = RoundFixtures.fourPlayerDraft()
        #expect(draft.wolf.teeOrder(for: draft.players) == ["zach", "sam", "alex", "jo"])
    }

    @Test func teeOrderMovesUpAndDownAndStaysAtTheEnds() {
        var draft = RoundFixtures.fourPlayerDraft()
        draft.wolf.move("alex", by: -1, players: draft.players)
        #expect(draft.wolf.teeOrder(for: draft.players) == ["zach", "alex", "sam", "jo"])
        draft.wolf.move("alex", by: -1, players: draft.players)
        #expect(draft.wolf.teeOrder(for: draft.players) == ["alex", "zach", "sam", "jo"])
        // Already first and last.
        draft.wolf.move("alex", by: -1, players: draft.players)
        draft.wolf.move("jo", by: 1, players: draft.players)
        #expect(draft.wolf.teeOrder(for: draft.players) == ["alex", "zach", "sam", "jo"])
        draft.wolf.move("zach", by: 1, players: draft.players)
        #expect(draft.wolf.teeOrder(for: draft.players) == ["alex", "sam", "zach", "jo"])
        // Not a player: nothing happens.
        draft.wolf.move("nobody", by: 1, players: draft.players)
        #expect(draft.wolf.teeOrder(for: draft.players) == ["alex", "sam", "zach", "jo"])
    }

    @Test func teeOrderFollowsPlayersAddedAndRemoved() {
        var draft = RoundFixtures.fourPlayerDraft()
        draft.wolf.move("jo", by: -1, players: draft.players)
        draft.wolf.move("jo", by: -1, players: draft.players)
        #expect(draft.wolf.teeOrder(for: draft.players) == ["zach", "jo", "sam", "alex"])

        // Sam leaves and Pat joins: Pat tees off last, the rest keep their order.
        draft.players.removeAll { $0.id == "sam" }
        draft.players.append(RoundDraft.Player(id: "pat", name: "Pat", courseHandicapText: "7"))
        #expect(draft.wolf.teeOrder(for: draft.players) == ["zach", "jo", "alex", "pat"])
    }

    @Test func resolvedTeeOrderIsAlwaysThePlayersOnce() {
        #expect(WolfTeeOrder.resolve(preferred: [], players: ["a", "b", "c", "d"]) == ["a", "b", "c", "d"])
        #expect(WolfTeeOrder.resolve(preferred: ["d", "x", "b", "b"], players: ["a", "b", "c", "d"]) == ["d", "b", "a", "c"])
        #expect(WolfTeeOrder.resolve(preferred: ["c", "a", "d", "b"], players: ["a", "b", "c", "d"]) == ["c", "a", "d", "b"])
    }

    @Test func roundTakesThePointValueAndTheTeeOrder() throws {
        var draft = RoundFixtures.fourPlayerDraft()
        draft.wolf.isEnabled = true
        draft.wolf.pointText = "2"
        draft.wolf.move("jo", by: -1, players: draft.players)

        let round = try draft.makeRound(using: bridge)
        #expect(round.playsWolf)
        #expect(round.wolfPointCents == 200)
        #expect(round.wolfTeeOrderIDs == ["zach", "sam", "jo", "alex"])
        #expect(round.wolfTeeOrder == ["zach", "sam", "jo", "alex"])
        let input = try #require(round.wolfInput)
        #expect(input.teeOrder == ["zach", "sam", "jo", "alex"])
        #expect(input.pointCents == 200)
        #expect(input.players == round.enginePlayers)
        #expect(input.holes == round.engineHoles)
        #expect(input.holeEvents.isEmpty)
    }

    @Test func sampleDraftPlaysWithoutWolfByDefault() throws {
        #expect(RoundDraft.sample.wolf.isEnabled == false)
        #expect(RoundDraft.sample.gameIssues().isEmpty)
    }
}
