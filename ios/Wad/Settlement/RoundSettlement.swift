import Foundation

/// Everything the settlement screen shows for a round. The per-game deltas,
/// the net positions and the payments all come from the engines; nothing here
/// adds up or splits money in Swift. All money is integer cents.
struct RoundSettlement: Equatable, Sendable {
    /// A player's result: positive = won, negative = owes.
    struct PlayerResult: Equatable, Identifiable, Sendable {
        var playerID: String
        var name: String
        /// Across all games, from the engine's settlement.
        var netCents: Int
        var skinsCents: Int
        var wadCents: Int
        var greeniesCents: Int
        /// Zero when Wolf is not played.
        var wolfCents: Int = 0
        /// The side games the player is out of; their amount is zero.
        var outOf: Set<SideGame> = []

        var id: String { playerID }

        func plays(_ game: SideGame) -> Bool {
            !outOf.contains(game)
        }

        func cents(_ game: SideGame) -> Int {
            switch game {
            case .skins: skinsCents
            case .wad: wadCents
            case .greenies: greeniesCents
            }
        }
    }

    /// One pairwise payment of the engine's settlement.
    struct Payment: Equatable, Sendable {
        var fromID: String
        var fromName: String
        var toID: String
        var toName: String
        var amountCents: Int
    }

    /// What one player owes another, net across the games, with the engine's
    /// reasons per game. Not a payment: the payments combine these.
    struct Debt: Equatable, Identifiable, Sendable {
        var fromID: String
        var fromName: String
        var toID: String
        var toName: String
        var amountCents: Int
        /// Signed toward the debt: a negative item is one the debtor won back.
        var items: [Engine.LedgerItem]

        var id: String { "\(fromID)>\(toID)" }
    }

    /// Every hole of the round, in order.
    var holeNumbers: [Int]
    /// Holes without a score from every player. The settlement is final when there are none.
    var incompleteHoles: [Int]
    /// In the order the players were added.
    var players: [PlayerResult]
    /// In the engine's order: largest creditor and debtor first.
    var payments: [Payment]
    /// The engine's pairwise ledger, in its order: by the debtor's id, then the creditor's.
    var debts: [Debt]
    var skins: Engine.SkinsResult
    /// Skins won per player id, from the engine's result: only the players in
    /// Skins, and nobody when Skins is not played.
    var ticks: [String: Int]
    /// The round's skins setting; off, a pushed hole pays nothing.
    var skinsCarryover: Bool
    var wadInstances: [Engine.WadInstanceResult]
    var greenieHoles: [Engine.GreenieHoleResult]
    var greeniesAmountCents: Int
    /// Nil when Wolf is not played, or unavailable (not exactly four players).
    var wolf: Engine.WolfResult?
    /// Wolf's value per point; nil when Wolf is not played.
    var wolfPointCents: Int?
    /// Display name per player id.
    var names: [String: String]

    @MainActor
    init(round: Round, bridge: EngineBridge) throws {
        let status = try RoundStatus(round: round, bridge: bridge)
        let settlement = try bridge.settle(status.gameDeltas)
        let names = Dictionary(
            round.players.map { ($0.playerID, $0.displayName) },
            uniquingKeysWith: { first, _ in first }
        )

        holeNumbers = round.orderedHoles.map(\.number)
        incompleteHoles = round.orderedHoles.map(\.number).filter { !round.isHoleComplete($0) }
        players = round.orderedPlayers.map { player in
            PlayerResult(
                playerID: player.playerID,
                name: player.displayName,
                netCents: settlement.positions[player.playerID] ?? 0,
                skinsCents: status.skins.deltas[player.playerID] ?? 0,
                wadCents: status.wad.deltas[player.playerID] ?? 0,
                greeniesCents: status.greenies.deltas[player.playerID] ?? 0,
                wolfCents: status.wolf?.deltas[player.playerID] ?? 0,
                outOf: Set(SideGame.allCases.filter { !player.plays($0) })
            )
        }
        payments = settlement.transfers.map { transfer in
            Payment(
                fromID: transfer.from,
                fromName: names[transfer.from] ?? Self.unknownPlayer,
                toID: transfer.to,
                toName: names[transfer.to] ?? Self.unknownPlayer,
                amountCents: transfer.amountCents
            )
        }
        debts = Self.debts(status.ledger, names: names)
        skins = status.skins
        ticks = status.ticks
        skinsCarryover = round.skinsCarryover
        wadInstances = status.wad.instances
        greenieHoles = status.greenies.holes
        greeniesAmountCents = round.greeniesAmountCents
        wolf = status.wolf
        wolfPointCents = round.wolfPointCents
        self.names = names
    }

    private static let unknownPlayer = "Unknown player"

    static func debts(_ ledger: [Engine.LedgerPair], names: [String: String]) -> [Debt] {
        ledger.map { pair in
            Debt(
                fromID: pair.from,
                fromName: names[pair.from] ?? unknownPlayer,
                toID: pair.to,
                toName: names[pair.to] ?? unknownPlayer,
                amountCents: pair.amountCents,
                items: pair.items
            )
        }
    }

    func name(_ playerID: String) -> String {
        names[playerID] ?? Self.unknownPlayer
    }

    /// The names of the players in the game, in order.
    func field(_ game: SideGame) -> [String] {
        players.filter { $0.plays(game) }.map(\.name)
    }

    /// At least two players are in the game.
    func isPlayed(_ game: SideGame) -> Bool {
        field(game).count >= SideGame.minimumPlayers
    }

    /// The players in the game when it is played and not everyone is in; nil otherwise.
    func partialField(_ game: SideGame) -> String? {
        let field = field(game)
        guard isPlayed(game), field.count < players.count else { return nil }
        return SettlementText.field(field)
    }

    /// Every hole has every player's score and, when Wolf is played, every Wolf
    /// hole is scored (`isWolfComplete`). Until then the numbers are provisional.
    var isFinal: Bool {
        incompleteHoles.isEmpty && isWolfComplete
    }

    var completedHoleCount: Int {
        holeNumbers.count - incompleteHoles.count
    }

    /// True when the holes scored so far are the first ones of the round, with no gap.
    var isScoredInOrder: Bool {
        incompleteHoles == Array(holeNumbers.dropFirst(completedHoleCount))
    }

    var lastHole: Int {
        holeNumbers.last ?? RoundDraft.holeCount
    }

    /// The skins value left over when the final hole was pushed. It is not paid
    /// out and is in no total (Open Question 1 in docs/domain-model.md). Nil
    /// while holes are still to be scored and when the final hole was won.
    var unresolvedSkinsCarryoverCents: Int? {
        skins.complete && skins.carryOutCents > 0 ? skins.carryOutCents : nil
    }

    /// Greenies that are recorded and not paid: the winner has no score of par
    /// or better on the hole.
    var unpaidGreenies: [Engine.GreenieHoleResult] {
        greenieHoles.filter { $0.status == .invalid || $0.status == .pending }
    }
}
