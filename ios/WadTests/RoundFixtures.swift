import Foundation
@testable import Wad

/// A par-72 course (the one in backend/test/engines/fixtures.ts) and four players.
enum RoundFixtures {
    static let pars = [4, 5, 3, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 4, 5, 3, 4, 4]
    static let strokeIndexes = [7, 11, 17, 3, 1, 15, 9, 5, 13, 8, 18, 2, 10, 6, 12, 16, 4, 14]

    /// A valid draft on a tee without rating and slope: handicaps are entered directly.
    static func unratedDraft() -> RoundDraft {
        var draft = RoundDraft()
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
