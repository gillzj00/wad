import Foundation

extension GameSnapshot {
    /// The round as recorded, with what the engines make of it. Without a
    /// status (no engine) only the score events can be found.
    @MainActor
    init(round: Round, status: RoundStatus?) {
        players = round.orderedPlayers.map { Player(id: $0.playerID, name: $0.displayName) }
        greenieAmountCents = round.greeniesAmountCents
        for hole in round.orderedHoles {
            for player in round.orderedPlayers {
                guard let gross = round.gross(playerID: player.playerID, hole: hole.number) else { continue }
                scores.append(Score(playerID: player.playerID, hole: hole.number, par: hole.par, gross: gross))
            }
        }
        guard let status else { return }
        skinWins = status.skins.holes.compactMap { result in
            guard result.status == .won, let winner = result.winnerUserId else { return nil }
            return SkinWin(hole: result.hole, winnerID: winner, atStakeCents: result.atStakeCents)
        }
        wadMakes = status.wad.instances.flatMap(\.makes).map {
            WadMake(hole: $0.hole, playerID: $0.userId, valueCents: $0.valueCents)
        }
        greenieWins = status.greenies.holes.compactMap { result in
            guard result.status == .awarded, let winner = result.winnerUserId else { return nil }
            return GreenieWin(hole: result.hole, winnerID: winner)
        }
        // HOOK: Wolf. `RoundStatus` has no Wolf result yet (W2); when it does,
        // map the holes won by the Wolf's side here.
    }

    /// The snapshot of a round, scored by the shared engine.
    @MainActor
    init(round: Round) {
        let status = SharedEngine.bridge.flatMap { try? RoundStatus(round: round, bridge: $0) }
        self.init(round: round, status: status)
    }
}
