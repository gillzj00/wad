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

    /// Every event present in this snapshot, in priority order.
    var events: [GameEvent] {
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
        return EventOrder.sorted(events, players: players)
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
/// that only changes what an event is worth does not replay it.
enum EventDetector {
    static func events(before: GameSnapshot, after: GameSnapshot) -> [GameEvent] {
        let seen = Set(before.events.map(\.identity))
        return after.events.filter { !seen.contains($0.identity) }
    }
}
