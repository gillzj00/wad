import Foundation

/// What the engines say about a round at one moment, reduced to what the
/// events are made of. Pure data: `EventDetector` compares two of them.
struct GameSnapshot: Equatable, Sendable {
    struct Player: Hashable, Sendable {
        var id: String
        var name: String
    }

    struct Score: Hashable, Sendable {
        var playerID: String
        var hole: Int
        var par: Int
        var gross: Int
    }

    struct SkinWin: Hashable, Sendable {
        var hole: Int
        var winnerID: String
        var atStakeCents: Int?
    }

    struct WadMake: Hashable, Sendable {
        var hole: Int
        var playerID: String
        var valueCents: Int
    }

    struct GreenieWin: Hashable, Sendable {
        var hole: Int
        var winnerID: String
    }

    /// A Wolf hole won by the Wolf's side. HOOK: the app does not play Wolf
    /// yet and `Engine` has no Wolf state, so nothing fills this in until W2
    /// lands; the detector and the show are ready for it.
    struct WolfWin: Hashable, Sendable {
        var hole: Int
        /// The Wolf first, then the partner if there was one.
        var winnerIDs: [String]
    }

    /// In tee order.
    var players: [Player]
    var scores: [Score] = []
    /// Holes the engine says are won outright, with carried value included.
    var skinWins: [SkinWin] = []
    /// Every make the engine counted, in order: each one changes hands.
    var wadMakes: [WadMake] = []
    var greenieWins: [GreenieWin] = []
    var greenieAmountCents: Int?
    var wolfWins: [WolfWin] = []

    /// The holes every player has a score on.
    var completeHoles: Set<Int> {
        let everyone = Set(players.map(\.id))
        guard !everyone.isEmpty else { return [] }
        let scored = Dictionary(grouping: scores, by: \.hole).mapValues { Set($0.map(\.playerID)) }
        return Set(scored.compactMap { hole, ids in everyone.isSubset(of: ids) ? hole : nil })
    }

    /// Every event present in this snapshot on a complete hole, in priority
    /// order. A partly scored hole has none, so its shows wait for the last
    /// score and then play together, whatever the engines say on the way.
    var events: [GameEvent] {
        let complete = completeHoles
        var events: [GameEvent] = []
        for score in scores {
            guard let kind = GameEventKind.scoreEvent(gross: score.gross, par: score.par) else { continue }
            events.append(GameEvent(
                kind: kind,
                hole: score.hole,
                playerIDs: [score.playerID],
                playerNames: [name(score.playerID)],
                otherNames: kind == .birdie ? players.filter { $0.id != score.playerID }.map(\.name) : []
            ))
        }
        for win in greenieWins {
            events.append(GameEvent(
                kind: .greenie,
                hole: win.hole,
                playerIDs: [win.winnerID],
                playerNames: [name(win.winnerID)],
                amountCents: greenieAmountCents
            ))
        }
        for make in wadMakes {
            events.append(GameEvent(
                kind: .wadTaken,
                hole: make.hole,
                playerIDs: [make.playerID],
                playerNames: [name(make.playerID)],
                amountCents: make.valueCents
            ))
        }
        for win in skinWins {
            events.append(GameEvent(
                kind: .skinWon,
                hole: win.hole,
                playerIDs: [win.winnerID],
                playerNames: [name(win.winnerID)],
                amountCents: win.atStakeCents
            ))
        }
        for win in wolfWins {
            events.append(GameEvent(
                kind: .wolfHoleWon,
                hole: win.hole,
                playerIDs: win.winnerIDs,
                playerNames: win.winnerIDs.map(name)
            ))
        }
        return EventOrder.sorted(events.filter { complete.contains($0.hole) }, players: players)
    }

    private func name(_ playerID: String) -> String {
        players.first { $0.id == playerID }?.name ?? "Unknown player"
    }
}

/// Priority first, then the hole, then tee order; stable for the rest.
enum EventOrder {
    static func sorted(_ events: [GameEvent], players: [GameSnapshot.Player]) -> [GameEvent] {
        let positions = Dictionary(players.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        func position(_ event: GameEvent) -> Int {
            event.playerIDs.first.flatMap { positions[$0] } ?? .max
        }
        return events.enumerated()
            .sorted { lhs, rhs in
                (lhs.element.kind, lhs.element.hole, position(lhs.element), lhs.offset)
                    < (rhs.element.kind, rhs.element.hole, position(rhs.element), rhs.offset)
            }
            .map(\.element)
    }
}

/// Which events to play after a change: the ones that are in the state after
/// it and were not in the state before. Re-saving the same score, or a
/// correction that takes an event away, plays nothing; a correction elsewhere
/// that only changes what an event is worth does not replay it. Clearing a
/// score leaves the hole incomplete without events, so scoring it again
/// plays the hole's events again.
enum EventDetector {
    static func events(before: GameSnapshot, after: GameSnapshot) -> [GameEvent] {
        let seen = Set(before.events.map(\.identity))
        return after.events.filter { !seen.contains($0.identity) }
    }
}

/// A gross score a change set or cleared (`gross` nil), for the phones
/// following the round live.
struct ScoreChange: Hashable, Sendable {
    var playerID: String
    var playerName: String
    var hole: Int
    var par: Int
    var gross: Int?
}

/// Which scores differ between two snapshots, in the order of the state after.
enum ScoreDetector {
    static func changes(before: GameSnapshot, after: GameSnapshot) -> [ScoreChange] {
        func key(_ score: GameSnapshot.Score) -> String { "\(score.playerID)/\(score.hole)" }
        func name(_ playerID: String) -> String {
            after.players.first { $0.id == playerID }?.name ?? "Unknown player"
        }
        let previous = Dictionary(before.scores.map { (key($0), $0) }, uniquingKeysWith: { first, _ in first })
        let current = Dictionary(after.scores.map { (key($0), $0) }, uniquingKeysWith: { first, _ in first })
        var changes: [ScoreChange] = after.scores.compactMap { score in
            guard previous[key(score)]?.gross != score.gross else { return nil }
            return ScoreChange(playerID: score.playerID, playerName: name(score.playerID), hole: score.hole, par: score.par, gross: score.gross)
        }
        for score in before.scores where current[key(score)] == nil {
            changes.append(ScoreChange(playerID: score.playerID, playerName: name(score.playerID), hole: score.hole, par: score.par, gross: nil))
        }
        return changes
    }
}
