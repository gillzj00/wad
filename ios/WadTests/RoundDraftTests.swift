import Foundation
import Testing
@testable import Wad

struct RoundDraftTests {
    // MARK: Course

    @Test func newDraftStartsWithEighteenParFoursAndBlankStrokeIndexes() {
        let draft = RoundDraft()
        #expect(draft.holes.map(\.number) == Array(1...18))
        #expect(draft.holes.allSatisfy { $0.par == 4 && $0.strokeIndexText.isEmpty })
        #expect(draft.totalPar == 72)
        #expect(draft.players.count == 2)
        #expect(draft.courseIssues() == [.courseNameMissing, .strokeIndexMissing(holes: Array(1...18))])
    }

    @Test func validCourseHasNoIssues() {
        #expect(RoundFixtures.unratedDraft().courseIssues().isEmpty)
        #expect(RoundFixtures.ratedDraft().courseIssues().isEmpty)
    }

    @Test func courseNameMustNotBeBlank() {
        var draft = RoundFixtures.unratedDraft()
        draft.courseName = "   "
        #expect(draft.courseIssues() == [.courseNameMissing])
    }

    @Test func strokeIndexesMustBeAPermutationOfOneToEighteen() {
        var draft = RoundFixtures.unratedDraft()

        // Hole 1 takes hole 5's stroke index 1, so 7 is no longer used.
        draft.holes[0].strokeIndexText = "1"
        #expect(draft.courseIssues() == [.strokeIndexDuplicate(strokeIndex: 1, holes: [1, 5])])
        #expect(draft.unusedStrokeIndexes == [7])

        draft.holes[0].strokeIndexText = ""
        #expect(draft.courseIssues() == [.strokeIndexMissing(holes: [1])])

        for text in ["0", "19", "-1", "1.5", "x"] {
            draft.holes[0].strokeIndexText = text
            #expect(draft.courseIssues() == [.strokeIndexOutOfRange(hole: 1)], "\(text)")
        }

        draft.holes[0].strokeIndexText = "7"
        #expect(draft.courseIssues().isEmpty)
        #expect(draft.unusedStrokeIndexes.isEmpty)
    }

    @Test func parMustBeThreeToFive() {
        var draft = RoundFixtures.unratedDraft()
        draft.holes[3].par = 2
        draft.holes[8].par = 6
        #expect(draft.courseIssues() == [.parOutOfRange(hole: 4), .parOutOfRange(hole: 9)])

        for par in 3...5 {
            draft.holes[3].par = par
            draft.holes[8].par = par
            #expect(draft.courseIssues().isEmpty)
        }
    }

    @Test func ratingAndSlopeAreGivenTogetherOrNotAtAll() {
        var draft = RoundFixtures.unratedDraft()
        #expect(draft.tee == nil)

        draft.ratingText = "72.5"
        #expect(draft.courseIssues() == [.ratingAndSlopeNotTogether])
        #expect(draft.tee == nil)

        draft.ratingText = ""
        draft.slopeText = "131"
        #expect(draft.courseIssues() == [.ratingAndSlopeNotTogether])
        #expect(draft.tee == nil)

        draft.ratingText = "72.5"
        #expect(draft.courseIssues().isEmpty)
        #expect(draft.tee == Engine.TeeRating(slope: 131, courseRating: 72.5, par: 72))
    }

    @Test func slopeMustBeFiftyFiveToOneFiftyFive() {
        var draft = RoundFixtures.ratedDraft()
        for text in ["54", "156", "0", "113.5", "abc", "-113"] {
            draft.slopeText = text
            #expect(draft.courseIssues() == [.slopeOutOfRange], "\(text)")
            #expect(draft.tee == nil)
        }
        for text in ["55", "113", "155"] {
            draft.slopeText = text
            #expect(draft.courseIssues().isEmpty, "\(text)")
        }
    }

    @Test func ratingMustBeANumber() {
        var draft = RoundFixtures.ratedDraft()
        for text in ["abc", "72.55", "-72", "0", "72."] {
            draft.ratingText = text
            #expect(draft.courseIssues() == [.ratingInvalid], "\(text)")
        }
        draft.ratingText = "72"
        #expect(draft.courseIssues().isEmpty)
    }

    @Test func teeParFollowsTheHoles() {
        var draft = RoundFixtures.ratedDraft()
        draft.holes[0].par = 5
        #expect(draft.tee?.par == 73)
    }

    // MARK: Players

    @Test func validPlayersHaveNoIssues() {
        #expect(RoundFixtures.unratedDraft().playerIssues().isEmpty)
        #expect(RoundFixtures.ratedDraft().playerIssues().isEmpty)
    }

    @Test func aRoundHasTwoToFourPlayers() {
        var draft = RoundFixtures.ratedDraft()
        draft.players.removeLast(3)
        #expect(draft.playerIssues() == [.playerCount])

        draft.players = RoundFixtures.ratedDraft().players
            + [RoundDraft.Player(id: "five", name: "Five", handicapIndexText: "10.0")]
        #expect(draft.playerIssues() == [.playerCount])
    }

    @Test func namesMustBeNonEmptyAndUnique() {
        var draft = RoundFixtures.unratedDraft()
        draft.players[1].name = "  "
        #expect(draft.playerIssues() == [.playerNameMissing(player: 2)])

        draft.players[1].name = " zach "
        #expect(draft.playerIssues() == [.playerNameDuplicate(name: "zach")])
    }

    @Test func withoutARatedTeeTheCourseHandicapIsEnteredDirectly() {
        var draft = RoundFixtures.unratedDraft()
        // The index is not used without a rated tee, so it is not validated either.
        draft.players[0].handicapIndexText = "garbage"
        #expect(draft.playerIssues().isEmpty)

        for text in ["", "15.5", "abc"] {
            draft.players[0].courseHandicapText = text
            #expect(draft.playerIssues() == [.courseHandicapInvalid(player: 1)], "\(text)")
        }
    }

    @Test func withARatedTeeTheIndexIsRequiredUnlessOverridden() {
        var draft = RoundFixtures.ratedDraft()
        draft.players[0].handicapIndexText = ""
        #expect(draft.playerIssues() == [.handicapIndexInvalid(player: 1)])

        draft.players[0].overridesCourseHandicap = true
        #expect(draft.playerIssues() == [.courseHandicapInvalid(player: 1)])

        draft.players[0].courseHandicapText = "16"
        #expect(draft.playerIssues().isEmpty)
    }

    @Test func courseHandicapComesFromTheEngineUnlessOverridden() throws {
        let bridge = try EngineBridge()
        let draft = RoundFixtures.ratedDraft()

        // 15.4 on 72.5 / 131 / par 72 is 18 in backend/test/engines/handicap.test.ts.
        #expect(try draft.computedCourseHandicap(for: draft.players[0], using: bridge) == 18)
        #expect(try draft.courseHandicap(for: draft.players[0], using: bridge) == 18)

        // Alex overrides the computed handicap with 20.
        let computed = try #require(try draft.computedCourseHandicap(for: draft.players[2], using: bridge))
        #expect(computed != 20)
        #expect(try draft.courseHandicap(for: draft.players[2], using: bridge) == 20)

        let unrated = RoundFixtures.unratedDraft()
        #expect(try unrated.computedCourseHandicap(for: unrated.players[0], using: bridge) == nil)
        #expect(try unrated.courseHandicap(for: unrated.players[0], using: bridge) == 15)
    }

    // MARK: Games

    @Test func gameAmountsDefaultToTheDomainModel() {
        let draft = RoundDraft()
        #expect(draft.gameIssues().isEmpty)
        #expect(draft.settings == GameSettings(wadStartCents: 700, wadStepCents: 200, skinsBaseCents: 500, greeniesAmountCents: 500))
        #expect(draft.settings == .defaults)
    }

    @Test func gameAmountsAreParsedToCents() {
        var draft = RoundDraft()
        draft.wadStartText = "10"
        draft.wadStepText = "2.5"
        draft.skinsBaseText = "1.25"
        draft.greeniesAmountText = "3.00"
        #expect(draft.settings == GameSettings(wadStartCents: 1000, wadStepCents: 250, skinsBaseCents: 125, greeniesAmountCents: 300))
    }

    @Test func invalidAmountsAreReportedPerGame() {
        var draft = RoundDraft()
        draft.wadStepText = "2.505"
        draft.greeniesAmountText = "-5"
        #expect(draft.gameIssues() == [.amountInvalid(game: "Wad step"), .amountInvalid(game: "Greenies")])
        #expect(draft.settings == nil)
    }

    // MARK: Round

    @Test func invalidDraftDoesNotMakeARound() throws {
        let bridge = try EngineBridge()
        var draft = RoundFixtures.unratedDraft()
        draft.holes[0].strokeIndexText = ""
        draft.skinsBaseText = "x"

        #expect(throws: SetupError.invalid([.strokeIndexMissing(holes: [1]), .amountInvalid(game: "Skins")])) {
            try draft.makeRound(using: bridge)
        }
    }

    @Test func everyIssueHasAMessage() {
        let issues: [SetupIssue] = [
            .courseNameMissing, .ratingAndSlopeNotTogether, .ratingInvalid, .slopeOutOfRange,
            .parOutOfRange(hole: 1), .strokeIndexMissing(holes: [1, 2]), .strokeIndexOutOfRange(hole: 1),
            .strokeIndexDuplicate(strokeIndex: 1, holes: [1, 5]), .playerCount, .playerNameMissing(player: 1),
            .playerNameDuplicate(name: "Zach"), .handicapIndexInvalid(player: 1),
            .courseHandicapInvalid(player: 1), .amountInvalid(game: "Skins"),
        ]
        #expect(Set(issues.map(\.message)).count == issues.count)
        #expect(SetupIssue.strokeIndexDuplicate(strokeIndex: 1, holes: [1, 5]).message == "Stroke index 1 is used on holes 1, 5.")
    }
}
