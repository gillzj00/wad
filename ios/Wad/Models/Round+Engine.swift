import Foundation

/// Pure mappings from the stored round to the game engines' inputs. The math
/// itself runs in `EngineBridge`.
extension Round {
    var enginePlayers: [Engine.Player] {
        orderedPlayers.map {
            Engine.Player(userId: $0.playerID, displayName: $0.displayName, courseHandicap: $0.courseHandicap)
        }
    }

    var enginePlayerIDs: [Engine.UserID] {
        orderedPlayers.map(\.playerID)
    }

    /// The game's players, in order.
    func enginePlayers(in game: SideGame) -> [Engine.Player] {
        players(in: game).map {
            Engine.Player(userId: $0.playerID, displayName: $0.displayName, courseHandicap: $0.courseHandicap)
        }
    }

    func enginePlayerIDs(in game: SideGame) -> [Engine.UserID] {
        players(in: game).map(\.playerID)
    }

    /// The scores of the game's players only.
    func engineScores(in game: SideGame) -> [Engine.Score] {
        let ids = Set(enginePlayerIDs(in: game))
        return engineScores.filter { ids.contains($0.userId) }
    }

    /// Handicap strokes per player id, allocated among the players in Skins: the
    /// lowest course handicap among them plays off scratch. Empty when Skins is
    /// not played. The engine calls these strokes "ticks".
    func skinsStrokes(using bridge: EngineBridge) throws -> [Engine.UserID: Engine.TicksByHole] {
        guard isPlayed(.skins) else { return [:] }
        return try bridge.allocateTicks(players: enginePlayers(in: .skins), holes: engineHoles)
    }

    var engineHoles: [Engine.HoleInfo] {
        orderedHoles.map { Engine.HoleInfo(hole: $0.number, par: $0.par, strokeIndex: $0.strokeIndex) }
    }

    /// Ordered by hole, then by player position.
    var engineScores: [Engine.Score] {
        let positions = Dictionary(players.map { ($0.playerID, $0.position) }, uniquingKeysWith: { first, _ in first })
        return scores
            .sorted {
                ($0.hole, positions[$0.playerID] ?? .max, $0.playerID)
                    < ($1.hole, positions[$1.playerID] ?? .max, $1.playerID)
            }
            .map { Engine.Score(userId: $0.playerID, hole: $0.hole, gross: $0.gross) }
    }

    /// Only the holes with something recorded.
    var engineHoleEvents: [Engine.HoleEvents] {
        orderedHoles
            .filter { !$0.wadMakerIDs.isEmpty || $0.greenieWinnerID != nil || $0.wolfEvent != nil }
            .map {
                Engine.HoleEvents(
                    hole: $0.number, wadMakers: $0.wadMakerIDs, greenieWinner: $0.greenieWinnerID, wolf: $0.wolfEvent
                )
            }
    }

    /// The tee's rating, when the course has one.
    var engineTeeRating: Engine.TeeRating? {
        guard let courseRating, let slope else { return nil }
        return Engine.TeeRating(slope: slope, courseRating: courseRating, par: totalPar)
    }

    var skinsInput: Engine.SkinsInput {
        Engine.SkinsInput(
            players: enginePlayers(in: .skins),
            holes: engineHoles,
            scores: engineScores(in: .skins),
            baseCents: skinsBaseCents,
            carryover: skinsCarryover
        )
    }

    var wadInput: Engine.WadInput {
        Engine.WadInput(
            players: enginePlayerIDs(in: .wad),
            holes: engineHoles,
            scores: engineScores(in: .wad),
            holeEvents: engineHoleEvents,
            startCents: wadStartCents,
            stepCents: wadStepCents
        )
    }

    var greeniesInput: Engine.GreeniesInput {
        Engine.GreeniesInput(
            players: enginePlayerIDs(in: .greenies),
            holes: engineHoles,
            scores: engineScores(in: .greenies),
            holeEvents: engineHoleEvents,
            amountCents: greeniesAmountCents
        )
    }
}
