import Foundation

/// What the scoring screen shows for Wolf on a hole, taken from the engine's
/// result for the hole and the running points. Nothing is scored here: who the
/// Wolf is, who is tied for last place and what the hole is worth all come
/// from the engine.
struct WolfHoleModel: Equatable, Sendable {
    struct Player: Equatable, Identifiable, Sendable {
        var playerID: String
        var name: String

        var id: String { playerID }
    }

    struct Standing: Equatable, Identifiable, Sendable {
        var player: Player
        var points: Int
        /// Fewest points of the four (shared when tied).
        var isLast: Bool
        /// Most points of the four (shared when tied).
        var isFirst: Bool

        var id: String { player.playerID }
    }

    var result: Engine.WolfHoleResult
    /// The Wolf of the hole, once known.
    var wolf: Player?
    /// Holes 17 and 18 with a tie for last place: the players the group picks
    /// the Wolf from. Empty otherwise.
    var tiedForLast: [Player]
    /// Who the group recorded as the Wolf, valid or not.
    var recordedWolfID: String?
    /// Everyone but the Wolf, in tee order. Empty while the Wolf is not known.
    var partnerCandidates: [Player]
    /// Running points in tee order.
    var standings: [Standing]
    var line: StatusLine

    init(result: Engine.WolfHoleResult, game: Engine.WolfResult, recordedWolfID: String?, name: (String) -> String) {
        func player(_ id: String) -> Player { Player(playerID: id, name: name(id)) }
        self.result = result
        wolf = result.wolfUserId.map(player)
        tiedForLast = (result.lastPlace ?? []).count > 1 ? (result.lastPlace ?? []).map(player) : []
        self.recordedWolfID = recordedWolfID
        partnerCandidates = result.wolfUserId.map { wolf in game.teeOrder.filter { $0 != wolf }.map(player) } ?? []
        let points = game.teeOrder.map { game.points[$0] ?? 0 }
        standings = game.teeOrder.map {
            let own = game.points[$0] ?? 0
            return Standing(player: player($0), points: own, isLast: own == points.min(), isFirst: own == points.max())
        }
        line = WolfText.hole(result, name: name)
    }

    var hole: Int { result.hole }

    /// The group has to pick the Wolf among `tiedForLast` before the hole can score.
    var needsWolf: Bool { result.status == .needsWolf }

    var choice: Engine.WolfChoice? { result.choice }
    var partnerID: String? { result.partnerUserId }

    /// The chips of the choice can be shown: the Wolf is known.
    var canChoose: Bool { wolf != nil }

    func isPartner(_ playerID: String) -> Bool {
        result.choice == .partner && result.partnerUserId == playerID
    }

    var isLone: Bool { result.choice == .lone }

    /// A recorded Wolf the engine refuses, to be cleared or changed.
    var hasRefusedWolf: Bool {
        result.status == .invalid && recordedWolfID != nil
            && (result.invalidReason == .wolfNotInLastPlace || result.invalidReason == .wolfContradictsRotation
                || result.invalidReason == .wolfNotAPlayer)
    }
}
