import Foundation

/// Wolf in the settlement. The points and the money are the engine's.
extension RoundSettlement {
    /// Wolf is not played, or every one of its 18 holes is won or tied. While a
    /// hole needs a Wolf, has no choice or is invalid, the round is not final.
    var isWolfComplete: Bool {
        wolf?.complete ?? true
    }

    /// Wolf is on for the round and the engine could not play it: the round
    /// does not have exactly four players.
    var isWolfUnavailable: Bool {
        wolfPointCents != nil && wolf == nil
    }

    /// The Wolf holes whose own record keeps them from being scored: a tie for
    /// last place without a recorded Wolf, a missing choice, or an invalid
    /// record. A hole 17 or 18 that only waits for earlier holes is not listed.
    var unscoredWolfHoles: [Engine.WolfHoleResult] {
        wolf?.holes.filter { hole in
            switch hole.status {
            case .needsWolf, .invalid: true
            case .pending: hole.choice == nil
            case .wonByWolfSide, .wonByOpponents, .tied: false
            }
        } ?? []
    }
}

extension RoundStatus {
    func wolfHole(_ hole: Int) -> Engine.WolfHoleResult? {
        wolf?.holes.first { $0.hole == hole }
    }

    /// Holes whose Wolf record the engine refuses to score: invalid or, on 17
    /// and 18, waiting for the group to pick the Wolf.
    var flaggedWolfHoles: [Int] {
        wolf?.holes.filter { $0.status == .invalid || $0.status == .needsWolf }.map(\.hole) ?? []
    }
}
