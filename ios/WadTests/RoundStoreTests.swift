import Foundation
import SwiftData
import Testing
@testable import Wad

@MainActor
struct RoundStoreTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainer(for: Round.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test func savesAndFetchesARound() throws {
        let context = container.mainContext

        context.insert(Round(courseName: "Pebble Beach"))
        try context.save()

        let rounds = try context.fetch(FetchDescriptor<Round>())
        #expect(rounds.map(\.courseName) == ["Pebble Beach"])
        #expect(rounds.first?.settings == .defaults)
    }

    /// Saves a full round in one context and reads it back in another.
    @Test func roundTripsCoursePlayersSettingsAndResults() throws {
        let bridge = try EngineBridge()
        var draft = RoundFixtures.ratedDraft()
        draft.wadStartText = "10"
        draft.skinsBaseText = "2.50"
        let startedAt = Date(timeIntervalSince1970: 1_790_000_000)

        let saved = try draft.makeRound(using: bridge, startedAt: startedAt)
        let context = container.mainContext
        context.insert(saved)
        saved.setGross(4, playerID: "zach", hole: 1)
        saved.setGross(5, playerID: "sam", hole: 1)
        saved.setGross(3, playerID: "jo", hole: 3)
        try #require(saved.hole(1)).wadMakerIDs = ["sam", "zach"]
        try #require(saved.hole(3)).greenieWinnerID = "jo"
        try context.save()

        let expectedPlayers = saved.enginePlayers
        let expectedWadInput = saved.wadInput
        let expectedSkinsInput = saved.skinsInput
        let expectedGreeniesInput = saved.greeniesInput

        let rounds = try ModelContext(container).fetch(FetchDescriptor<Round>())
        #expect(rounds.count == 1)
        let round = try #require(rounds.first)

        #expect(round.id == saved.id)
        #expect(round.courseName == "Pebble Beach")
        #expect(round.startedAt == startedAt)
        #expect(round.courseRating == 72.5)
        #expect(round.slope == 131)
        #expect(round.settings == GameSettings(wadStartCents: 1000, wadStepCents: 200, skinsBaseCents: 250, greeniesAmountCents: 500))

        #expect(round.holes.count == 18)
        #expect(round.orderedHoles.map(\.par) == RoundFixtures.pars)
        #expect(round.orderedHoles.map(\.strokeIndex) == RoundFixtures.strokeIndexes)
        #expect(round.hole(1)?.wadMakerIDs == ["sam", "zach"])
        #expect(round.hole(2)?.wadMakerIDs == [])
        #expect(round.hole(3)?.greenieWinnerID == "jo")
        #expect(round.hole(1)?.greenieWinnerID == nil)

        #expect(round.orderedPlayers.map(\.displayName) == ["Zach", "Sam", "Alex", "Jo"])
        #expect(round.orderedPlayers.map(\.courseHandicap) == [18, 9, 20, -1])
        #expect(round.orderedPlayers.map(\.handicapIndex) == [15.4, 7.0, 22.3, -1.2])
        #expect(round.enginePlayers == expectedPlayers)

        #expect(round.scores.count == 3)
        #expect(round.gross(playerID: "zach", hole: 1) == 4)
        #expect(round.gross(playerID: "sam", hole: 1) == 5)
        #expect(round.gross(playerID: "jo", hole: 3) == 3)
        #expect(round.gross(playerID: "jo", hole: 1) == nil)

        #expect(round.wadInput == expectedWadInput)
        #expect(round.skinsInput == expectedSkinsInput)
        #expect(round.greeniesInput == expectedGreeniesInput)
    }

    @Test func deletingARoundDeletesItsHolesPlayersAndScores() throws {
        let bridge = try EngineBridge()
        let context = container.mainContext
        let round = try RoundFixtures.unratedDraft().makeRound(using: bridge)
        context.insert(round)
        round.setGross(4, playerID: "zach", hole: 1)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<RoundHole>()) == 18)
        #expect(try context.fetchCount(FetchDescriptor<RoundPlayer>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<HoleScore>()) == 1)

        context.delete(round)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<Round>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<RoundHole>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<RoundPlayer>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<HoleScore>()) == 0)
    }
}
