import Foundation
import SwiftData
import Testing
@testable import Wad

/// Recording scores, Wad makers and greenies, and that every change is stored.
@MainActor
struct RoundScorerTests {
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

    /// The round as another context reads it from the store.
    func storedRound() throws -> Round {
        try #require(try ModelContext(container).fetch(FetchDescriptor<Round>()).first)
    }

    // MARK: Scores

    @Test func recordsCorrectsAndClearsAScore() throws {
        try scorer.setGross(5, playerID: "zach", hole: 1)
        #expect(round.gross(playerID: "zach", hole: 1) == 5)

        try scorer.setGross(4, playerID: "zach", hole: 1)
        #expect(round.gross(playerID: "zach", hole: 1) == 4)
        #expect(round.scores.count == 1)

        try scorer.setGross(nil, playerID: "zach", hole: 1)
        #expect(round.gross(playerID: "zach", hole: 1) == nil)
        #expect(round.scores.isEmpty)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<HoleScore>()) == 0)
    }

    @Test func firstStepGivesParWhateverTheDirection() throws {
        // Hole 2 is a par 5, hole 3 a par 3.
        try scorer.stepGross(by: 1, playerID: "zach", hole: 2)
        try scorer.stepGross(by: -1, playerID: "sam", hole: 2)
        try scorer.stepGross(by: 0, playerID: "alex", hole: 3)
        #expect(round.gross(playerID: "zach", hole: 2) == 5)
        #expect(round.gross(playerID: "sam", hole: 2) == 5)
        #expect(round.gross(playerID: "alex", hole: 3) == 3)
    }

    @Test func laterStepsMoveTheScoreWithinTheRange() throws {
        try scorer.stepGross(by: 1, playerID: "zach", hole: 3)
        try scorer.stepGross(by: 1, playerID: "zach", hole: 3)
        #expect(round.gross(playerID: "zach", hole: 3) == 4)

        try scorer.stepGross(by: 0, playerID: "zach", hole: 3)
        #expect(round.gross(playerID: "zach", hole: 3) == 4)

        for _ in 0..<10 { try scorer.stepGross(by: -1, playerID: "zach", hole: 3) }
        #expect(round.gross(playerID: "zach", hole: 3) == 1)

        for _ in 0..<30 { try scorer.stepGross(by: 1, playerID: "zach", hole: 3) }
        #expect(round.gross(playerID: "zach", hole: 3) == 20)
    }

    @Test func parForTheRestKeepsScoresAlreadyEntered() throws {
        try scorer.setGross(6, playerID: "sam", hole: 1)
        try scorer.setParForUnscored(hole: 1)
        #expect(round.gross(playerID: "zach", hole: 1) == 4)
        #expect(round.gross(playerID: "sam", hole: 1) == 6)
        #expect(round.gross(playerID: "alex", hole: 1) == 4)
    }

    @Test func rejectsUnknownHolesPlayersAndImpossibleScores() throws {
        #expect(throws: ScoringError.unknownHole(19)) { try scorer.setGross(4, playerID: "zach", hole: 19) }
        #expect(throws: ScoringError.unknownPlayer("nobody")) { try scorer.setGross(4, playerID: "nobody", hole: 1) }
        #expect(throws: ScoringError.grossOutOfRange(0)) { try scorer.setGross(0, playerID: "zach", hole: 1) }
        #expect(throws: ScoringError.grossOutOfRange(21)) { try scorer.setGross(21, playerID: "zach", hole: 1) }
        #expect(throws: ScoringError.unknownPlayer("nobody")) { try scorer.addWadMaker(playerID: "nobody", hole: 1) }
        #expect(round.scores.isEmpty)
        #expect(scorer.wadMakers(hole: 1).isEmpty)
    }

    @Test func tracksCompletedHoles() throws {
        #expect(round.completedHoles.isEmpty)
        #expect(round.firstIncompleteHole == 1)

        try scorer.setParForUnscored(hole: 1)
        try scorer.setGross(4, playerID: "zach", hole: 2)
        try scorer.setParForUnscored(hole: 3)
        #expect(round.completedHoles == [1, 3])
        #expect(round.isHoleComplete(2) == false)
        #expect(round.firstIncompleteHole == 2)

        for hole in 1...18 { try scorer.setParForUnscored(hole: hole) }
        #expect(round.completedHoles.count == 18)
        #expect(round.firstIncompleteHole == nil)
    }

    // MARK: Wad

    @Test func keepsWadMakersInTheOrderAdded() throws {
        try scorer.addWadMaker(playerID: "sam", hole: 5)
        try scorer.addWadMaker(playerID: "alex", hole: 5)
        try scorer.addWadMaker(playerID: "zach", hole: 5)

        #expect(scorer.wadMakers(hole: 5) == ["sam", "alex", "zach"])
        #expect(scorer.wadOrder(playerID: "sam", hole: 5) == 1)
        #expect(scorer.wadOrder(playerID: "alex", hole: 5) == 2)
        #expect(scorer.wadOrder(playerID: "zach", hole: 5) == 3)
        #expect(scorer.wadMakers(hole: 6).isEmpty)
        #expect(scorer.wadOrder(playerID: "sam", hole: 6) == nil)
    }

    @Test func aPlayerIsAMakerAtMostOncePerHole() throws {
        #expect(try scorer.addWadMaker(playerID: "sam", hole: 5) == true)
        #expect(try scorer.addWadMaker(playerID: "zach", hole: 5) == true)
        #expect(try scorer.addWadMaker(playerID: "sam", hole: 5) == false)
        #expect(scorer.wadMakers(hole: 5) == ["sam", "zach"])

        // The same player can make one on another hole.
        #expect(try scorer.addWadMaker(playerID: "sam", hole: 6) == true)
        #expect(scorer.wadMakers(hole: 6) == ["sam"])

        let wad = try bridge.scoreWad(round.wadInput)
        #expect(wad.ignored.isEmpty)
    }

    @Test func reordersByRemovingAndAddingAgain() throws {
        try scorer.toggleWadMaker(playerID: "sam", hole: 5)
        try scorer.toggleWadMaker(playerID: "alex", hole: 5)
        try scorer.toggleWadMaker(playerID: "zach", hole: 5)

        try scorer.toggleWadMaker(playerID: "sam", hole: 5)
        #expect(scorer.wadMakers(hole: 5) == ["alex", "zach"])
        #expect(scorer.wadOrder(playerID: "alex", hole: 5) == 1)

        try scorer.toggleWadMaker(playerID: "sam", hole: 5)
        #expect(scorer.wadMakers(hole: 5) == ["alex", "zach", "sam"])

        try scorer.removeWadMaker(playerID: "zach", hole: 5)
        try scorer.removeWadMaker(playerID: "zach", hole: 5)
        #expect(scorer.wadMakers(hole: 5) == ["alex", "sam"])
    }

    // MARK: Greenies

    @Test func offersOnlyPlayersWithParOrBetterOnAPar3() throws {
        // Hole 3 is a par 3.
        #expect(scorer.greenieCandidates(hole: 3).isEmpty)

        try scorer.setGross(3, playerID: "zach", hole: 3)
        try scorer.setGross(4, playerID: "sam", hole: 3)
        #expect(scorer.greenieCandidates(hole: 3).map(\.playerID) == ["zach"])

        try scorer.setGross(2, playerID: "alex", hole: 3)
        #expect(scorer.greenieCandidates(hole: 3).map(\.playerID) == ["zach", "alex"])

        // Hole 1 is a par 4: no greenie, whatever the scores.
        try scorer.setGross(3, playerID: "zach", hole: 1)
        #expect(scorer.greenieCandidates(hole: 1).isEmpty)
    }

    @Test func recordsAndClearsTheGreenieWinner() throws {
        try scorer.setGross(3, playerID: "zach", hole: 3)
        try scorer.setGreenieWinner("zach", hole: 3)
        #expect(round.hole(3)?.greenieWinnerID == "zach")

        try scorer.setGreenieWinner(nil, hole: 3)
        #expect(round.hole(3)?.greenieWinnerID == nil)
    }

    @Test func rejectsAWinnerWhoIsNotEligible() throws {
        try scorer.setGross(4, playerID: "sam", hole: 3)
        try scorer.setGross(3, playerID: "zach", hole: 1)

        #expect(throws: ScoringError.greenieNotEligible(playerID: "sam", hole: 3)) {
            try scorer.setGreenieWinner("sam", hole: 3)
        }
        #expect(throws: ScoringError.greenieNotEligible(playerID: "alex", hole: 3)) {
            try scorer.setGreenieWinner("alex", hole: 3)
        }
        #expect(throws: ScoringError.greenieNotOnPar3(hole: 1)) {
            try scorer.setGreenieWinner("zach", hole: 1)
        }
        #expect(throws: ScoringError.unknownPlayer("nobody")) {
            try scorer.setGreenieWinner("nobody", hole: 3)
        }
        #expect(round.hole(3)?.greenieWinnerID == nil)
        #expect(round.hole(1)?.greenieWinnerID == nil)
    }

    /// A winner whose score is changed afterwards stays recorded, is reported
    /// invalid by the engine and is not paid until the group fixes the hole.
    @Test func aWinnerWhoNoLongerQualifiesIsInvalidAndNotPaid() throws {
        try scorer.setGross(3, playerID: "zach", hole: 3)
        try scorer.setGross(3, playerID: "sam", hole: 3)
        try scorer.setGross(4, playerID: "alex", hole: 3)
        try scorer.setGreenieWinner("zach", hole: 3)

        var status = try RoundStatus(round: round, bridge: bridge)
        #expect(status.greenieHole(3) == Engine.GreenieHoleResult(hole: 3, winnerUserId: "zach", status: .awarded))
        #expect(status.greenies.deltas == ["zach": 1000, "sam": -500, "alex": -500])
        #expect(status.invalidGreenieHoles.isEmpty)

        try scorer.stepGross(by: 1, playerID: "zach", hole: 3)

        #expect(round.hole(3)?.greenieWinnerID == "zach")
        #expect(scorer.greenieCandidates(hole: 3).map(\.playerID) == ["sam"])
        status = try RoundStatus(round: round, bridge: bridge)
        #expect(status.greenieHole(3) == Engine.GreenieHoleResult(hole: 3, winnerUserId: "zach", status: .invalid))
        #expect(status.greenies.deltas == ["zach": 0, "sam": 0, "alex": 0])
        #expect(status.invalidGreenieHoles == [3])
        let line = ScoringText.greenie(try #require(status.greenieHole(3)), amountCents: 500) { $0.capitalized }
        #expect(line.isWarning)
        #expect(line.title == "Not paid: Zach did not score par or better")

        // A cleared score leaves the winner waiting for one.
        try scorer.setGross(nil, playerID: "zach", hole: 3)
        status = try RoundStatus(round: round, bridge: bridge)
        #expect(status.greenieHole(3)?.status == .pending)
        #expect(status.greenies.deltas == ["zach": 0, "sam": 0, "alex": 0])

        // Fixed by choosing the player who does qualify.
        try scorer.setGreenieWinner("sam", hole: 3)
        status = try RoundStatus(round: round, bridge: bridge)
        #expect(status.greenieHole(3)?.status == .awarded)
        #expect(status.greenies.deltas == ["zach": -500, "sam": 1000, "alex": -500])
        #expect(status.invalidGreenieHoles.isEmpty)
    }

    // MARK: Persistence

    @Test func everyChangeIsStoredStraightAway() throws {
        try scorer.setGross(5, playerID: "zach", hole: 1)
        #expect(try storedRound().gross(playerID: "zach", hole: 1) == 5)

        try scorer.stepGross(by: -1, playerID: "zach", hole: 1)
        #expect(try storedRound().gross(playerID: "zach", hole: 1) == 4)

        try scorer.setGross(nil, playerID: "zach", hole: 1)
        #expect(try storedRound().gross(playerID: "zach", hole: 1) == nil)

        try scorer.setParForUnscored(hole: 3)
        #expect(try storedRound().completedHoles == [3])

        try scorer.addWadMaker(playerID: "sam", hole: 3)
        try scorer.addWadMaker(playerID: "zach", hole: 3)
        #expect(try storedRound().hole(3)?.wadMakerIDs == ["sam", "zach"])

        try scorer.removeWadMaker(playerID: "sam", hole: 3)
        #expect(try storedRound().hole(3)?.wadMakerIDs == ["zach"])

        try scorer.setGreenieWinner("alex", hole: 3)
        #expect(try storedRound().hole(3)?.greenieWinnerID == "alex")

        try scorer.setGreenieWinner(nil, hole: 3)
        #expect(try storedRound().hole(3)?.greenieWinnerID == nil)
    }

    @Test func aStoredRoundScoresTheSameAfterReadingItBack() throws {
        try scorer.setParForUnscored(hole: 1)
        try scorer.setParForUnscored(hole: 2)
        try scorer.setGross(4, playerID: "zach", hole: 2)
        try scorer.setParForUnscored(hole: 3)
        try scorer.addWadMaker(playerID: "alex", hole: 2)
        try scorer.addWadMaker(playerID: "sam", hole: 2)
        try scorer.setGreenieWinner("sam", hole: 3)

        let expected = try RoundStatus(round: round, bridge: bridge)
        let stored = try storedRound()

        #expect(stored.engineScores == round.engineScores)
        #expect(stored.engineHoleEvents == [
            Engine.HoleEvents(hole: 2, wadMakers: ["alex", "sam"]),
            Engine.HoleEvents(hole: 3, greenieWinner: "sam"),
        ])
        #expect(try RoundStatus(round: stored, bridge: bridge) == expected)
        #expect(Scorecard(round: stored) == Scorecard(round: round))
    }
}
