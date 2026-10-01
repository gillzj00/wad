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

    func snapshot(
        scores: [GameSnapshot.Score] = [],
        skinWins: [GameSnapshot.SkinWin] = [],
        wadMakes: [GameSnapshot.WadMake] = [],
        greenieWins: [GameSnapshot.GreenieWin] = [],
        wolfWins: [GameSnapshot.WolfWin] = []
    ) -> GameSnapshot {
        GameSnapshot(
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
