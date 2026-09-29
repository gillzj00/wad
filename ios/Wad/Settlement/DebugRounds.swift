#if DEBUG
import Foundation

/// Finished rounds for simulator runs, previews and the UI tests
/// (`-debugSeedRound`). Only what was recorded is seeded; the results come
/// from the engines like for any other round.
@MainActor
enum DebugRounds {
    /// A finished round whose last four holes push, so $20.00 of skins is unresolved.
    ///
    /// Zach (15) gets a tick on the holes with stroke index 1 to 8 (holes 1, 4,
    /// 5, 8, 10, 12, 14 and 17) against Sam and Alex (7). Everybody makes par on
    /// every hole, except that Zach makes a bogey on hole 17. Sam makes a Wad
    /// putt on hole 2 and Alex wins the greenie on hole 3.
    static func finalPush(using bridge: EngineBridge) throws -> Round {
        var draft = RoundDraft.sample
        draft.courseName = "Carryover Links"
        draft.ratingText = ""
        draft.slopeText = ""
        draft.players = [
            RoundDraft.Player(id: "zach", name: "Zach", courseHandicapText: "15"),
            RoundDraft.Player(id: "sam", name: "Sam", courseHandicapText: "7"),
            RoundDraft.Player(id: "alex", name: "Alex", courseHandicapText: "7"),
        ]
        let round = try draft.makeRound(using: bridge)

        for hole in round.holes {
            for player in round.players {
                round.setGross(hole.par, playerID: player.playerID, hole: hole.number)
            }
        }
        round.setGross(5, playerID: "zach", hole: 17)
        round.hole(2)?.wadMakerIDs = ["sam"]
        round.hole(3)?.greenieWinnerID = "alex"
        return round
    }
}
#endif
