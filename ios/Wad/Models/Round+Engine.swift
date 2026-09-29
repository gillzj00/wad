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
            .filter { !$0.wadMakerIDs.isEmpty || $0.greenieWinnerID != nil }
            .map { Engine.HoleEvents(hole: $0.number, wadMakers: $0.wadMakerIDs, greenieWinner: $0.greenieWinnerID) }
    }

    /// The tee's rating, when the course has one.
    var engineTeeRating: Engine.TeeRating? {
        guard let courseRating, let slope else { return nil }
        return Engine.TeeRating(slope: slope, courseRating: courseRating, par: totalPar)
    }

    var skinsInput: Engine.SkinsInput {
        Engine.SkinsInput(players: enginePlayers, holes: engineHoles, scores: engineScores, baseCents: skinsBaseCents)
    }

    var wadInput: Engine.WadInput {
        Engine.WadInput(
            players: enginePlayerIDs,
            holes: engineHoles,
            scores: engineScores,
            holeEvents: engineHoleEvents,
            startCents: wadStartCents,
            stepCents: wadStepCents
        )
    }

    var greeniesInput: Engine.GreeniesInput {
        Engine.GreeniesInput(
            players: enginePlayerIDs,
            holes: engineHoles,
            scores: engineScores,
            holeEvents: engineHoleEvents,
            amountCents: greeniesAmountCents
        )
    }
}
