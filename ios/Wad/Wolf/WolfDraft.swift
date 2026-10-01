import Foundation

/// The tee order of a Wolf round: the four players in a fixed order.
enum WolfTeeOrder {
    /// `preferred` without the ids that are not players (each at most once),
    /// then the players it leaves out in their own order. The result is always a
    /// permutation of `players`, so it is what the engine needs.
    static func resolve(preferred: [String], players: [String]) -> [String] {
        var seen = Set<String>()
        var order = preferred.filter { players.contains($0) && seen.insert($0).inserted }
        order += players.filter { !seen.contains($0) }
        return order
    }

    /// `order` with the player moved one place up (-1) or down (+1). Unchanged
    /// when the player is not in it or is already at that end.
    static func moving(_ playerID: String, by offset: Int, in order: [String]) -> [String] {
        guard let index = order.firstIndex(of: playerID), order.indices.contains(index + offset) else { return order }
        var moved = order
        moved.swapAt(index, index + offset)
        return moved
    }
}

/// The Wolf settings of the setup flow: whether it is played, the value of a
/// point and the tee order. Wolf needs exactly four players (ADR-0012).
struct WolfDraft: Equatable, Sendable {
    static let playerCount = 4
    /// $1 a point (docs/domain-model.md, Game 4).
    static let defaultPointCents = 100

    var isEnabled = false
    var pointText = Money.dollars(fromCents: WolfDraft.defaultPointCents)
    /// The players' ids as reordered so far. Players not in it tee off after
    /// them in the order they were added; see `teeOrder(for:)`.
    var teeOrderIDs: [String] = []

    var pointCents: Int? { Money.cents(fromDollars: pointText) }

    static func canBePlayed(playerCount: Int) -> Bool {
        playerCount == Self.playerCount
    }

    /// The tee order for these players: the order they were added, as reordered.
    func teeOrder(for players: [RoundDraft.Player]) -> [String] {
        WolfTeeOrder.resolve(preferred: teeOrderIDs, players: players.map(\.id))
    }

    /// Moves the player one place up (-1) or down (+1) in the tee order.
    mutating func move(_ playerID: String, by offset: Int, players: [RoundDraft.Player]) {
        teeOrderIDs = WolfTeeOrder.moving(playerID, by: offset, in: teeOrder(for: players))
    }

    /// Nothing when Wolf is off. On, it needs four players and a valid amount.
    func issues(playerCount: Int) -> [SetupIssue] {
        guard isEnabled else { return [] }
        var issues: [SetupIssue] = []
        if !Self.canBePlayed(playerCount: playerCount) { issues.append(.wolfNeedsFourPlayers) }
        if pointCents == nil { issues.append(.amountInvalid(game: "Wolf")) }
        return issues
    }

    /// Puts the settings on the round. Nothing is stored when Wolf is off.
    func apply(to round: Round, players: [RoundDraft.Player]) {
        guard isEnabled, let pointCents else { return }
        round.wolfPointCents = pointCents
        round.wolfTeeOrderIDs = teeOrder(for: players)
    }
}
