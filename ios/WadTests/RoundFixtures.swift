import Foundation
@testable import Wad

/// A par-72 course (the one in backend/test/engines/fixtures.ts) and four players.
enum RoundFixtures {
    static let pars = [4, 5, 3, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 4, 5, 3, 4, 4]
    static let strokeIndexes = [7, 11, 17, 3, 1, 15, 9, 5, 13, 8, 18, 2, 10, 6, 12, 16, 4, 14]

    /// A valid draft on a tee without rating and slope: handicaps are entered
    /// directly. Its holes start unscored, like every draft built on it.
    static func unratedDraft() -> RoundDraft {
        var draft = RoundDraft()
        draft.startsEveryHoleAtPar = false
        draft.courseName = "Pebble Beach"
        draft.holes = (0..<18).map {
            RoundDraft.Hole(number: $0 + 1, par: pars[$0], strokeIndexText: String(strokeIndexes[$0]))
        }
        draft.players = [
            RoundDraft.Player(id: "zach", name: "Zach", courseHandicapText: "15"),
            RoundDraft.Player(id: "sam", name: "Sam", courseHandicapText: "7"),
        ]
        return draft
    }

    /// The unrated draft with a third player: Zach (15) gets 8 ticks against Sam and Alex (7).
    static func threePlayerDraft() -> RoundDraft {
        var draft = unratedDraft()
        draft.players.append(RoundDraft.Player(id: "alex", name: "Alex", courseHandicapText: "7"))
        return draft
    }

    /// The unrated draft with four players: Zach (15) gets 8 ticks and Alex (10)
    /// gets 3 against Sam and Jo (7).
    static func fourPlayerDraft() -> RoundDraft {
        var draft = unratedDraft()
        draft.players.append(RoundDraft.Player(id: "alex", name: "Alex", courseHandicapText: "10"))
        draft.players.append(RoundDraft.Player(id: "jo", name: "Jo", courseHandicapText: "7"))
        return draft
    }

    /// The course and players of the UI walkthrough: every hole a par 4 except
    /// the third (par 3), stroke indexes 1 to 18 in order, so Zach (15) gets a
    /// tick on holes 1 to 8 against Sam and Alex (7).
    static func walkthroughDraft() -> RoundDraft {
        var draft = threePlayerDraft()
        draft.courseName = "Walkthrough Links"
        draft.holes = (1...18).map {
            RoundDraft.Hole(number: $0, par: $0 == 3 ? 3 : 4, strokeIndexText: String($0))
        }
        return draft
    }

    /// A valid draft on a rated tee (72.5 / 131) with four players, one overridden.
    static func ratedDraft() -> RoundDraft {
        var draft = unratedDraft()
        draft.ratingText = "72.5"
        draft.slopeText = "131"
        draft.players = [
            RoundDraft.Player(id: "zach", name: "Zach", handicapIndexText: "15.4"),
            RoundDraft.Player(id: "sam", name: "Sam", handicapIndexText: "7.0"),
            RoundDraft.Player(
                id: "alex",
                name: "Alex",
                handicapIndexText: "22.3",
                courseHandicapText: "20",
                overridesCourseHandicap: true
            ),
            RoundDraft.Player(id: "jo", name: "Jo", handicapIndexText: "+1.2"),
        ]
        return draft
    }
}
