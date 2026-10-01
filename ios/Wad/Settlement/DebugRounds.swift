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
    /// putt on hole 2 and Alex wins the greenie on hole 3. Zach and Sam have a
    /// Venmo handle, Alex has none.
    static func finalPush(using bridge: EngineBridge, startedAt: Date = .now) throws -> Round {
        var draft = RoundDraft.sample
        draft.courseName = "Carryover Links"
        draft.ratingText = ""
        draft.slopeText = ""
        draft.players = [
            RoundDraft.Player(id: "zach", name: "Zach", courseHandicapText: "15", venmoHandleText: "@zach-golf"),
            RoundDraft.Player(id: "sam", name: "Sam", courseHandicapText: "7", venmoHandleText: "sam_golfs"),
            RoundDraft.Player(id: "alex", name: "Alex", courseHandicapText: "7"),
        ]
        let round = try draft.makeRound(using: bridge, startedAt: startedAt)

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

    /// A finished round with every kind of score, from an eagle to a double
    /// bogey, and no carryover left: Jo wins the last hole. The sample course
    /// and its four players. On hole 7, a par 5, Zach makes a birdie, Sam a
    /// bogey, Alex a double bogey and Jo an eagle.
    static func showcase(using bridge: EngineBridge, startedAt: Date = .now) throws -> Round {
        var draft = RoundDraft.sample
        draft.players[0].venmoHandleText = "@zach-golf"
        draft.players[3].venmoHandleText = "jo-birdies"
        let round = try draft.makeRound(using: bridge, startedAt: startedAt)

        // Strokes over or under par, hole by hole, in the order of the players.
        let toPar = [
            [1, 0, 0, 1, 2, 0, -1, 1, 0, 0, 1, 0, 1, 0, 1, 0, 2, 1],
            [0, -1, 0, 0, 1, 0, 1, 0, -1, 1, 0, 0, 0, -1, 0, 1, 0, 0],
            [1, 1, 1, 0, 2, 1, 2, 2, 1, 1, 0, 1, 2, 0, 1, 1, 1, 1],
            [0, 0, -1, 0, 0, 0, -2, 0, 0, -1, 0, -1, 0, 0, 0, 0, -1, -1],
        ]
        for (player, strokes) in zip(round.orderedPlayers, toPar) {
            for hole in round.orderedHoles {
                round.setGross(hole.par + strokes[hole.number - 1], playerID: player.playerID, hole: hole.number)
            }
        }
        let ids = round.orderedPlayers.map(\.playerID)
        round.hole(2)?.wadMakerIDs = [ids[1]]
        round.hole(5)?.wadMakerIDs = [ids[3], ids[0]]
        round.hole(12)?.wadMakerIDs = [ids[2]]
        round.hole(3)?.greenieWinnerID = ids[3]
        round.hole(11)?.greenieWinnerID = ids[1]
        return round
    }

    /// A round that is being played: seven holes scored.
    static func inProgress(using bridge: EngineBridge, startedAt: Date = .now) throws -> Round {
        var draft = RoundDraft.sample
        draft.courseName = "Morning Links"
        draft.players.removeLast()
        let round = try draft.makeRound(using: bridge, startedAt: startedAt)
        let toPar = [[1, 0, 1, 0, 2, 0, 0], [0, 0, -1, 1, 0, 0, 1], [1, 2, 0, 1, 1, 1, 0]]
        for (player, strokes) in zip(round.orderedPlayers, toPar) {
            for (offset, stroke) in strokes.enumerated() {
                guard let hole = round.hole(offset + 1) else { continue }
                round.setGross(hole.par + stroke, playerID: player.playerID, hole: hole.number)
            }
        }
        return round
    }

    /// A Wolf round through hole 16, with three players tied for last place, so
    /// hole 17 asks the group to pick the Wolf. Four players with the same
    /// handicap (no ticks), tee order Zach, Sam, Alex, Jo, $1 a point. Everyone
    /// makes par and the Wolf goes alone (a tied hole) except:
    ///  1  Zach alone makes 3: Zach 4
    ///  2  Sam alone makes 4 on the par 5: Sam 4
    ///  3  Alex takes Jo and makes 2: Alex 2, Jo 2
    ///  4  Jo alone, Zach makes 3: Zach, Sam, Alex +1  ->  5 5 3 2
    ///  8  Jo takes Alex and makes 3: Alex 5, Jo 4
    /// 12  Jo alone makes 4 on the par 5: Jo 8       ->  5 5 5 8
    static func wolf(using bridge: EngineBridge, startedAt: Date = .now) throws -> Round {
        var draft = RoundDraft.sample
        draft.courseName = "Wolf Hollow"
        draft.ratingText = ""
        draft.slopeText = ""
        draft.players = ["Zach", "Sam", "Alex", "Jo"].map {
            RoundDraft.Player(id: $0.lowercased(), name: $0, courseHandicapText: "7")
        }
        draft.wolf.isEnabled = true
        let round = try draft.makeRound(using: bridge, startedAt: startedAt)

        let birdies: [Int: String] = [1: "zach", 2: "sam", 3: "alex", 4: "zach", 8: "jo", 12: "jo"]
        let partners: [Int: String] = [3: "jo", 8: "alex"]
        for hole in round.orderedHoles where hole.number <= 16 {
            for player in round.players {
                let gross = birdies[hole.number] == player.playerID ? hole.par - 1 : hole.par
                round.setGross(gross, playerID: player.playerID, hole: hole.number)
            }
            if let partner = partners[hole.number] {
                hole.wolfChoice = Engine.WolfChoice.partner.rawValue
                hole.wolfPartnerID = partner
            } else {
                hole.wolfChoice = Engine.WolfChoice.lone.rawValue
            }
        }
        return round
    }

    /// The rounds of `-debugSeedRound gallery`: one being played, a finished
    /// one and, the oldest, the one with the unresolved carryover.
    static func gallery(using bridge: EngineBridge, startedAt: Date = .now) throws -> [Round] {
        let day: TimeInterval = 24 * 60 * 60
        return [
            try inProgress(using: bridge, startedAt: startedAt),
            try showcase(using: bridge, startedAt: startedAt - 2 * day),
            try finalPush(using: bridge, startedAt: startedAt - 9 * day),
        ]
    }
}
#endif
