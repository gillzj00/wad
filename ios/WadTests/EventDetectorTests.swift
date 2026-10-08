import Foundation
import Testing
@testable import Wad

/// Which events a change to the round triggers, from the engine state before
/// and after it.
struct EventDetectorTests {
    let players = [
        GameSnapshot.Player(id: "zach", name: "Zach"),
        GameSnapshot.Player(id: "sam", name: "Sam"),
        GameSnapshot.Player(id: "alex", name: "Alex"),
    ]

    /// Events play only on a hole every player has scored. `fillingHoles`
    /// completes every hole the snapshot mentions with par for the players
    /// without a score there (par is the hole's other scores', or 4), so a
    /// test about one score or one game sees its event.
    func snapshot(
        players: [GameSnapshot.Player]? = nil,
        scores: [GameSnapshot.Score] = [],
        skinWins: [GameSnapshot.SkinWin] = [],
        wadMakes: [GameSnapshot.WadMake] = [],
        greenieWins: [GameSnapshot.GreenieWin] = [],
        wolfWins: [GameSnapshot.WolfWin] = [],
        fillingHoles: Bool = true
    ) -> GameSnapshot {
        let players = players ?? self.players
        var scores = scores
        if fillingHoles {
            let holes = Set(scores.map(\.hole) + skinWins.map(\.hole) + wadMakes.map(\.hole)
                + greenieWins.map(\.hole) + wolfWins.map(\.hole))
            for hole in holes.sorted() {
                let par = scores.first { $0.hole == hole }?.par ?? 4
                for player in players where !scores.contains(where: { $0.hole == hole && $0.playerID == player.id }) {
                    scores.append(score(player.id, hole: hole, par: par, gross: par))
                }
            }
        }
        return GameSnapshot(
            players: players,
            scores: scores,
            skinWins: skinWins,
            wadMakes: wadMakes,
            greenieWins: greenieWins,
            greenieAmountCents: 500,
            wolfWins: wolfWins
        )
    }

    func score(_ playerID: String, hole: Int, par: Int, gross: Int) -> GameSnapshot.Score {
        GameSnapshot.Score(playerID: playerID, hole: hole, par: par, gross: gross)
    }

    func kinds(before: GameSnapshot, after: GameSnapshot) -> [GameEventKind] {
        EventDetector.events(before: before, after: after).map(\.kind)
    }

    // MARK: Score events

    @Test(arguments: [
        (par: 4, gross: 1, kind: GameEventKind.holeInOne),
        (par: 3, gross: 1, kind: .holeInOne),
        (par: 5, gross: 2, kind: .albatross),
        (par: 4, gross: 2, kind: .eagle),
        (par: 5, gross: 3, kind: .eagle),
        (par: 4, gross: 3, kind: .birdie),
        (par: 3, gross: 2, kind: .birdie),
        (par: 4, gross: 8, kind: .snowman),
        (par: 5, gross: 8, kind: .snowman),
    ])
    func aScoreTriggersItsEvent(par: Int, gross: Int, kind: GameEventKind) {
        let after = snapshot(scores: [score("zach", hole: 7, par: par, gross: gross)])
        let events = EventDetector.events(before: snapshot(), after: after)
        #expect(events.map(\.kind) == [kind])
        #expect(events.first?.hole == 7)
        #expect(events.first?.playerIDs == ["zach"])
        #expect(events.first?.playerNames == ["Zach"])
    }

    @Test(arguments: [(par: 4, gross: 4), (par: 4, gross: 5), (par: 4, gross: 6), (par: 4, gross: 7), (par: 3, gross: 3)])
    func parAndMostBogeysTriggerNothing(par: Int, gross: Int) {
        let after = snapshot(scores: [score("zach", hole: 1, par: par, gross: gross)])
        #expect(kinds(before: snapshot(), after: after).isEmpty)
    }

    /// Only exactly 8 is a snowman until the owner says otherwise.
    @Test(arguments: [9, 10, 12, 20])
    func nineAndWorseAreNotASnowman(gross: Int) {
        let after = snapshot(scores: [score("zach", hole: 1, par: 4, gross: gross)])
        #expect(kinds(before: snapshot(), after: after).isEmpty)
    }

    @Test func aHoleInOneIsNotAlsoAnEagle() {
        let after = snapshot(scores: [score("zach", hole: 3, par: 3, gross: 1)])
        #expect(kinds(before: snapshot(), after: after) == [.holeInOne])
    }

    @Test func theBirdieIsAddressedToTheOthers() {
        let after = snapshot(scores: [score("sam", hole: 2, par: 5, gross: 4)])
        let event = EventDetector.events(before: snapshot(), after: after).first
        #expect(event?.otherNames == ["Zach", "Alex"])
        #expect(EventText.subtitle(event!) == "From Sam to Zach and Alex")
    }

    // MARK: Game events

    @Test func aGreenieTriggersWithItsAmount() {
        let after = snapshot(greenieWins: [GameSnapshot.GreenieWin(hole: 3, winnerID: "alex")])
        let events = EventDetector.events(before: snapshot(), after: after)
        #expect(events.map(\.kind) == [.greenie])
        #expect(events.first?.amountCents == 500)
        #expect(EventText.subtitle(events.first!) == "Alex takes $5.00 a head on hole 3")
    }

    @Test func aWadMakeTriggersWithTheValueAfterIt() {
        let before = snapshot(wadMakes: [GameSnapshot.WadMake(hole: 2, playerID: "sam", valueCents: 700)])
        let after = snapshot(wadMakes: [
            GameSnapshot.WadMake(hole: 2, playerID: "sam", valueCents: 700),
            GameSnapshot.WadMake(hole: 5, playerID: "zach", valueCents: 900),
        ])
        let events = EventDetector.events(before: before, after: after)
        #expect(events.map(\.kind) == [.wadTaken])
        #expect(events.first?.playerIDs == ["zach"])
        #expect(events.first?.amountCents == 900)
        #expect(EventText.subtitle(events.first!) == "Zach holds the Wad at $9.00")
    }

    @Test func aSkinTriggersWithTheCarriedValue() {
        let after = snapshot(skinWins: [GameSnapshot.SkinWin(hole: 4, winnerID: "sam", atStakeCents: 1500)])
        let events = EventDetector.events(before: snapshot(), after: after)
        #expect(events.map(\.kind) == [.skinWon])
        #expect(EventText.subtitle(events.first!) == "Sam takes $15.00 a head on hole 4")
    }

    @Test func aWolfHoleTriggersForTheWinningSide() {
        let after = snapshot(wolfWins: [GameSnapshot.WolfWin(hole: 6, winnerIDs: ["zach", "sam"])])
        let events = EventDetector.events(before: snapshot(), after: after)
        #expect(events.map(\.kind) == [.wolfHoleWon])
        #expect(EventText.subtitle(events.first!) == "Zach and Sam take hole 6")

        let lone = snapshot(wolfWins: [GameSnapshot.WolfWin(hole: 6, winnerIDs: ["zach"])])
        #expect(EventText.subtitle(EventDetector.events(before: snapshot(), after: lone).first!) == "Lone Wolf Zach takes hole 6")
    }

    // MARK: No replays

    @Test func reSavingTheSameScorePlaysNothing() {
        let state = snapshot(
            scores: [score("zach", hole: 1, par: 4, gross: 3)],
            skinWins: [GameSnapshot.SkinWin(hole: 1, winnerID: "zach", atStakeCents: 500)]
        )
        #expect(kinds(before: state, after: state).isEmpty)
    }

    @Test func aCorrectionThatRemovesAnEventPlaysNothing() {
        let before = snapshot(
            scores: [score("zach", hole: 1, par: 4, gross: 2)],
            skinWins: [GameSnapshot.SkinWin(hole: 1, winnerID: "zach", atStakeCents: 500)]
        )
        let after = snapshot(scores: [score("zach", hole: 1, par: 4, gross: 4)])
        #expect(kinds(before: before, after: after).isEmpty)
    }

    @Test func aCorrectionThatOnlyChangesWhatASkinIsWorthDoesNotReplayIt() {
        let before = snapshot(skinWins: [GameSnapshot.SkinWin(hole: 3, winnerID: "sam", atStakeCents: 1500)])
        let after = snapshot(skinWins: [GameSnapshot.SkinWin(hole: 3, winnerID: "sam", atStakeCents: 500)])
        #expect(kinds(before: before, after: after).isEmpty)
    }

    @Test func aCorrectionThatMovesTheSkinToAnotherPlayerPlaysIt() {
        let before = snapshot(skinWins: [GameSnapshot.SkinWin(hole: 3, winnerID: "sam", atStakeCents: 500)])
        let after = snapshot(skinWins: [GameSnapshot.SkinWin(hole: 3, winnerID: "alex", atStakeCents: 500)])
        let events = EventDetector.events(before: before, after: after)
        #expect(events.map(\.playerIDs) == [["alex"]])
    }

    @Test func steppingAScoreDownPlaysEachNewEventOnce() {
        let four = snapshot(scores: [score("zach", hole: 1, par: 4, gross: 4)])
        let three = snapshot(scores: [score("zach", hole: 1, par: 4, gross: 3)])
        let two = snapshot(scores: [score("zach", hole: 1, par: 4, gross: 2)])
        #expect(kinds(before: four, after: three) == [.birdie])
        #expect(kinds(before: three, after: two) == [.eagle])
        #expect(kinds(before: two, after: three) == [.birdie])
    }

    // MARK: Complete holes

    @Test func aTwoPlayerHolePlaysOnceBothScoresAreIn() {
        let two = Array(players.prefix(2))
        let greenie = GameSnapshot.GreenieWin(hole: 3, winnerID: "zach")
        let skin = GameSnapshot.SkinWin(hole: 3, winnerID: "zach", atStakeCents: 500)
        let empty = snapshot(players: two, fillingHoles: false)
        let zachIn = snapshot(
            players: two,
            scores: [score("zach", hole: 3, par: 3, gross: 2)],
            skinWins: [skin],
            greenieWins: [greenie],
            fillingHoles: false
        )
        #expect(kinds(before: empty, after: zachIn).isEmpty)

        let bothIn = snapshot(
            players: two,
            scores: [score("zach", hole: 3, par: 3, gross: 2), score("sam", hole: 3, par: 3, gross: 3)],
            skinWins: [skin],
            greenieWins: [greenie],
            fillingHoles: false
        )
        let events = EventDetector.events(before: zachIn, after: bothIn)
        #expect(events.map(\.kind) == [.greenie, .skinWon, .birdie])
        #expect(events.allSatisfy { $0.hole == 3 && $0.playerIDs == ["zach"] })
    }

    /// Four players scored one at a time, the way the scoring screen does it:
    /// the skin moves from Sam to Zach on the way, and nothing plays until Jo's
    /// score completes the hole. Then the hole's events play together, in order.
    @Test func aFourPlayerHolePlaysNothingUntilTheLastScoreLands() {
        let four = players + [GameSnapshot.Player(id: "jo", name: "Jo")]
        let greenie = GameSnapshot.GreenieWin(hole: 3, winnerID: "zach")
        let wad = GameSnapshot.WadMake(hole: 3, playerID: "zach", valueCents: 700)
        func step(_ scores: [GameSnapshot.Score], skinWinner: String?) -> GameSnapshot {
            snapshot(
                players: four,
                scores: scores,
                skinWins: skinWinner.map { [GameSnapshot.SkinWin(hole: 3, winnerID: $0, atStakeCents: 500)] } ?? [],
                wadMakes: [wad],
                greenieWins: [greenie],
                fillingHoles: false
            )
        }
        let scores = [
            score("sam", hole: 3, par: 3, gross: 3),
            score("zach", hole: 3, par: 3, gross: 2),
            score("alex", hole: 3, par: 3, gross: 4),
            score("jo", hole: 3, par: 3, gross: 4),
        ]
        let steps = [
            step([], skinWinner: nil),
            step(Array(scores.prefix(1)), skinWinner: "sam"),
            step(Array(scores.prefix(2)), skinWinner: "zach"),
            step(Array(scores.prefix(3)), skinWinner: "zach"),
        ]
        for (before, after) in zip(steps, steps.dropFirst()) {
            #expect(kinds(before: before, after: after).isEmpty)
        }

        let complete = step(scores, skinWinner: "zach")
        let events = EventDetector.events(before: steps[3], after: complete)
        #expect(events.map(\.kind) == [.greenie, .wadTaken, .skinWon, .birdie])
        #expect(events.allSatisfy { $0.hole == 3 && $0.playerIDs == ["zach"] })
    }

    @Test func aCorrectionOnACompleteHolePlaysOnlyWhatIsNew() {
        let before = snapshot(
            scores: [score("zach", hole: 1, par: 4, gross: 3), score("sam", hole: 1, par: 4, gross: 4), score("alex", hole: 1, par: 4, gross: 4)],
            skinWins: [GameSnapshot.SkinWin(hole: 1, winnerID: "zach", atStakeCents: 500)],
            fillingHoles: false
        )
        let after = snapshot(
            scores: [score("zach", hole: 1, par: 4, gross: 3), score("sam", hole: 1, par: 4, gross: 3), score("alex", hole: 1, par: 4, gross: 4)],
            fillingHoles: false
        )
        let events = EventDetector.events(before: before, after: after)
        #expect(events.map(\.kind) == [.birdie])
        #expect(events.first?.playerIDs == ["sam"])
    }

    @Test func anIncompleteHoleWithAGreenieWinnerPlaysNothing() {
        let after = snapshot(
            scores: [score("zach", hole: 3, par: 3, gross: 2), score("sam", hole: 3, par: 3, gross: 3)],
            greenieWins: [GameSnapshot.GreenieWin(hole: 3, winnerID: "zach")],
            fillingHoles: false
        )
        #expect(after.events.isEmpty)
        #expect(kinds(before: snapshot(fillingHoles: false), after: after).isEmpty)
    }

    /// Clearing a score makes the hole incomplete again, so entering it again
    /// plays the hole's events again.
    @Test func clearingAScoreOnACompleteHolePlaysNothingAndReEnteringItReplays() {
        let scores = [score("zach", hole: 1, par: 4, gross: 3), score("sam", hole: 1, par: 4, gross: 4), score("alex", hole: 1, par: 4, gross: 4)]
        let skin = GameSnapshot.SkinWin(hole: 1, winnerID: "zach", atStakeCents: 500)
        let complete = snapshot(scores: scores, skinWins: [skin], fillingHoles: false)
        let cleared = snapshot(scores: Array(scores.prefix(2)), skinWins: [skin], fillingHoles: false)
        #expect(kinds(before: complete, after: cleared).isEmpty)
        #expect(kinds(before: cleared, after: complete) == [.skinWon, .birdie])
    }

    @Test func aCompleteHolePlaysWhileAnotherIsPartlyScored() {
        let after = snapshot(
            scores: [
                score("zach", hole: 1, par: 4, gross: 3), score("sam", hole: 1, par: 4, gross: 4), score("alex", hole: 1, par: 4, gross: 4),
                score("zach", hole: 2, par: 5, gross: 3),
            ],
            fillingHoles: false
        )
        #expect(after.events.map { "\($0.kind)@\($0.hole)" } == ["birdie@1"])
    }

    // MARK: Priority

    @Test func severalEventsFromOneScorePlayInPriorityOrder() {
        let after = snapshot(
            scores: [score("zach", hole: 4, par: 4, gross: 2)],
            skinWins: [GameSnapshot.SkinWin(hole: 4, winnerID: "zach", atStakeCents: 1000)],
            wadMakes: [GameSnapshot.WadMake(hole: 4, playerID: "zach", valueCents: 700)]
        )
        #expect(kinds(before: snapshot(), after: after) == [.eagle, .wadTaken, .skinWon])
    }

    @Test func everyKindInPriorityOrder() {
        let after = snapshot(
            scores: [
                score("zach", hole: 1, par: 4, gross: 3),
                score("sam", hole: 1, par: 4, gross: 8),
                score("alex", hole: 2, par: 5, gross: 3),
                score("zach", hole: 3, par: 3, gross: 1),
                score("sam", hole: 4, par: 5, gross: 2),
            ],
            skinWins: [GameSnapshot.SkinWin(hole: 2, winnerID: "alex", atStakeCents: 500)],
            wadMakes: [GameSnapshot.WadMake(hole: 1, playerID: "sam", valueCents: 700)],
            greenieWins: [GameSnapshot.GreenieWin(hole: 3, winnerID: "zach")],
            wolfWins: [GameSnapshot.WolfWin(hole: 1, winnerIDs: ["zach"])]
        )
        #expect(kinds(before: snapshot(), after: after) == [
            .holeInOne, .albatross, .eagle, .greenie, .wadTaken, .skinWon, .wolfHoleWon, .snowman, .birdie,
        ])
    }

    @Test func theSameKindPlaysByHoleThenTeeOrder() {
        let after = snapshot(scores: [
            score("alex", hole: 2, par: 4, gross: 3),
            score("sam", hole: 1, par: 4, gross: 3),
            score("zach", hole: 1, par: 4, gross: 3),
        ])
        let events = EventDetector.events(before: snapshot(), after: after)
        #expect(events.map { "\($0.playerIDs[0])@\($0.hole)" } == ["zach@1", "sam@1", "alex@2"])
    }

    // MARK: Text

    @Test func titlesAndNameLists() {
        #expect(EventText.list(["Zach"]) == "Zach")
        #expect(EventText.list(["Zach", "Sam"]) == "Zach and Sam")
        #expect(EventText.list(["Zach", "Sam", "Alex"]) == "Zach, Sam and Alex")
        let event = GameEvent(kind: .holeInOne, hole: 12, playerIDs: ["zach"], playerNames: ["Zach"])
        #expect(EventText.title(event) == "Hole in one")
        #expect(EventText.subtitle(event) == "Zach on hole 12")
        #expect(EventText.subtitle(GameEvent(kind: .snowman, hole: 5, playerIDs: ["sam"], playerNames: ["Sam"]))
            == "Sam takes an 8 on hole 5")
    }
}
