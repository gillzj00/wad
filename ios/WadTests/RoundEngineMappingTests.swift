import Foundation
import SwiftData
import Testing
@testable import Wad

/// The round's mappings to the engine inputs, and the engines run on them.
@MainActor
struct RoundEngineMappingTests {
    let container: ModelContainer
    let bridge: EngineBridge

    init() throws {
        container = try ModelContainer(for: Round.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        bridge = try EngineBridge()
    }

    func makeRound(_ draft: RoundDraft) throws -> Round {
        let round = try draft.makeRound(using: bridge)
        container.mainContext.insert(round)
        try container.mainContext.save()
        return round
    }

    @Test func mapsPlayersInTheOrderAdded() throws {
        let round = try makeRound(RoundFixtures.ratedDraft())

        // Course handicaps on 72.5 / 131 / par 72: 15.4 -> 18, 7.0 -> 9, +1.2 -> -1; Alex is overridden to 20.
        #expect(round.enginePlayers == [
            Engine.Player(userId: "zach", displayName: "Zach", courseHandicap: 18),
            Engine.Player(userId: "sam", displayName: "Sam", courseHandicap: 9),
            Engine.Player(userId: "alex", displayName: "Alex", courseHandicap: 20),
            Engine.Player(userId: "jo", displayName: "Jo", courseHandicap: -1),
        ])
        #expect(round.enginePlayerIDs == ["zach", "sam", "alex", "jo"])
        #expect(round.orderedPlayers.map(\.handicapIndex) == [15.4, 7.0, 22.3, -1.2])
        #expect(round.engineTeeRating == Engine.TeeRating(slope: 131, courseRating: 72.5, par: 72))
    }

    @Test func unratedRoundKeepsTheEnteredCourseHandicaps() throws {
        let round = try makeRound(RoundFixtures.unratedDraft())

        #expect(round.enginePlayers == [
            Engine.Player(userId: "zach", displayName: "Zach", courseHandicap: 15),
            Engine.Player(userId: "sam", displayName: "Sam", courseHandicap: 7),
        ])
        #expect(round.orderedPlayers.map(\.handicapIndex) == [nil, nil])
        #expect(round.engineTeeRating == nil)
        #expect(round.courseRating == nil)
        #expect(round.slope == nil)
    }

    @Test func mapsHolesInOrder() throws {
        let round = try makeRound(RoundFixtures.unratedDraft())

        #expect(round.engineHoles == (0..<18).map {
            Engine.HoleInfo(hole: $0 + 1, par: RoundFixtures.pars[$0], strokeIndex: RoundFixtures.strokeIndexes[$0])
        })
        #expect(round.totalPar == 72)
    }

    @Test func mapsScoresByHoleThenPlayer() throws {
        let round = try makeRound(RoundFixtures.unratedDraft())
        #expect(round.engineScores.isEmpty)

        round.setGross(5, playerID: "sam", hole: 2)
        round.setGross(4, playerID: "sam", hole: 1)
        round.setGross(6, playerID: "zach", hole: 2)
        round.setGross(5, playerID: "zach", hole: 1)
        // Corrected score replaces the first one; a cleared score goes away.
        round.setGross(4, playerID: "zach", hole: 1)
        round.setGross(3, playerID: "zach", hole: 3)
        round.setGross(nil, playerID: "zach", hole: 3)
        try container.mainContext.save()

        #expect(round.engineScores == [
            Engine.Score(userId: "zach", hole: 1, gross: 4),
            Engine.Score(userId: "sam", hole: 1, gross: 4),
            Engine.Score(userId: "zach", hole: 2, gross: 6),
            Engine.Score(userId: "sam", hole: 2, gross: 5),
        ])
        #expect(round.gross(playerID: "zach", hole: 1) == 4)
        #expect(round.gross(playerID: "zach", hole: 3) == nil)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<HoleScore>()) == 4)
    }

    @Test func mapsHoleEventsKeepingTheOrderOfWadMakers() throws {
        let round = try makeRound(RoundFixtures.ratedDraft())
        #expect(round.engineHoleEvents.isEmpty)

        try #require(round.hole(5)).wadMakerIDs = ["sam", "alex", "zach"]
        try #require(round.hole(3)).greenieWinnerID = "jo"
        try #require(round.hole(6)).wadMakerIDs = ["jo"]
        try #require(round.hole(6)).greenieWinnerID = "zach"

        #expect(round.engineHoleEvents == [
            Engine.HoleEvents(hole: 3, greenieWinner: "jo"),
            Engine.HoleEvents(hole: 5, wadMakers: ["sam", "alex", "zach"]),
            Engine.HoleEvents(hole: 6, wadMakers: ["jo"], greenieWinner: "zach"),
        ])
    }

    @Test func gameInputsCarryTheRoundsSettings() throws {
        var draft = RoundFixtures.unratedDraft()
        draft.wadStartText = "10"
        draft.wadStepText = "2.50"
        draft.skinsBaseText = "1"
        draft.greeniesAmountText = "3"
        let round = try makeRound(draft)
        round.setGross(3, playerID: "zach", hole: 3)
        try #require(round.hole(3)).greenieWinnerID = "zach"

        #expect(round.skinsInput == Engine.SkinsInput(
            players: round.enginePlayers,
            holes: round.engineHoles,
            scores: [Engine.Score(userId: "zach", hole: 3, gross: 3)],
            baseCents: 100,
            carryover: true
        ))
        #expect(round.wadInput == Engine.WadInput(
            players: ["zach", "sam"],
            holes: round.engineHoles,
            scores: [Engine.Score(userId: "zach", hole: 3, gross: 3)],
            holeEvents: [Engine.HoleEvents(hole: 3, greenieWinner: "zach")],
            startCents: 1000,
            stepCents: 250
        ))
        #expect(round.greeniesInput == Engine.GreeniesInput(
            players: ["zach", "sam"],
            holes: round.engineHoles,
            scores: [Engine.Score(userId: "zach", hole: 3, gross: 3)],
            holeEvents: [Engine.HoleEvents(hole: 3, greenieWinner: "zach")],
            amountCents: 300
        ))
    }

    @Test func defaultSettingsReachTheGameInputs() throws {
        let round = try makeRound(RoundFixtures.unratedDraft())
        #expect(round.settings == .defaults)
        #expect(round.wadInput.startCents == 700)
        #expect(round.wadInput.stepCents == 200)
        #expect(round.skinsInput.baseCents == 500)
        #expect(round.skinsInput.carryover == true)
        #expect(round.greeniesInput.amountCents == 500)
    }

    @Test func skinsInputCarriesTheRoundsCarryoverSetting() throws {
        let round = try makeRound(RoundFixtures.unratedDraft())
        #expect(round.skinsCarryover == true)
        #expect(round.skinsInput.carryover == true)
        round.skinsCarryover = false
        #expect(round.skinsInput.carryover == false)
        #expect(round.skinsInput.baseCents == 500)
    }

    /// Left out, the bridge sends no `carryover` and the engine carries over.
    @Test func skinsInputWithoutCarryoverSettingCarriesOver() throws {
        let round = try makeRound(RoundFixtures.unratedDraft())
        for hole in 1...2 {
            round.setGross(4, playerID: "zach", hole: hole)
            round.setGross(4, playerID: "sam", hole: hole)
        }
        var input = round.skinsInput
        input.carryover = nil
        // Hole 1 is a tick for Zach (stroke index 7 is within 8 ticks): he wins it. Hole 2 pushes, hole 3 carries.
        let result = try bridge.scoreSkins(input)
        #expect(result.holes[0].status == .won)
        #expect(result.holes[1].status == .pushed)
        #expect(result.holes[2].carriedInCents == 500)
        #expect(result.holes[2].atStakeCents == 1000)
    }

    /// The domain model's examples, scored from a stored round through the real bundle.
    @Test func enginesAcceptTheMappedInputs() throws {
        let round = try makeRound(RoundFixtures.unratedDraft())

        // 15 against 7: Zach gets 8 ticks, on stroke indexes 1 to 8.
        let ticks = try bridge.allocateTicks(players: round.enginePlayers, holes: round.engineHoles)
        #expect(ticks["zach"]?.values.reduce(0, +) == 8)
        #expect(ticks["sam"]?.values.reduce(0, +) == 0)
        #expect(ticks["zach"]?[5] == 1)
        #expect(ticks["zach"]?[3] == 0)

        // Hole 3 (par 3, stroke index 17): Sam's 3 beats Zach's 4 and wins the greenie.
        round.setGross(4, playerID: "zach", hole: 3)
        round.setGross(3, playerID: "sam", hole: 3)
        try #require(round.hole(3)).greenieWinnerID = "sam"
        // Hole 5 (stroke index 1): Zach's 5 nets 4 and ties Sam's 4.
        round.setGross(5, playerID: "zach", hole: 5)
        round.setGross(4, playerID: "sam", hole: 5)
        try #require(round.hole(5)).wadMakerIDs = ["zach", "sam"]

        let greenies = try bridge.scoreGreenies(round.greeniesInput)
        #expect(greenies.deltas == ["zach": -500, "sam": 500])

        let skins = try bridge.scoreSkins(round.skinsInput)
        #expect(skins.holes[4].net == ["zach": 4, "sam": 4])

        let wad = try bridge.scoreWad(round.wadInput)
        let front = try #require(wad.instances.first)
        #expect(front.holderUserId == "sam")
        #expect(front.valueCents == 900)
        #expect(wad.ignored.isEmpty)
    }
}
