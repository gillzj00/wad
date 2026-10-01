import Foundation

/// Wolf on the stored round: the settings, the tee order and the mapping to
/// the engine's input. The scoring runs in the engine (`EngineBridge.scoreWolf`).
extension Round {
    /// Wolf is part of the round when it has a value per point.
    var playsWolf: Bool {
        wolfPointCents != nil
    }

    /// The players' ids in the order they tee off: the stored order, with the
    /// players it leaves out after them in the order they were added.
    var wolfTeeOrder: [String] {
        WolfTeeOrder.resolve(preferred: wolfTeeOrderIDs, players: enginePlayerIDs)
    }

    /// Changing the tee order after play started would change who was the Wolf
    /// on holes already played, so it is locked once the round has a score or
    /// a Wolf record (ADR-0012).
    var isWolfTeeOrderLocked: Bool {
        !scores.isEmpty || holes.contains { $0.wolfEvent != nil }
    }

    /// Nil when Wolf is not played. The engine returns nothing for it unless
    /// the round has exactly four players.
    var wolfInput: Engine.WolfInput? {
        guard let wolfPointCents else { return nil }
        return Engine.WolfInput(
            players: enginePlayers,
            teeOrder: wolfTeeOrder,
            holes: engineHoles,
            scores: engineScores,
            holeEvents: engineHoleEvents,
            pointCents: wolfPointCents
        )
    }
}

extension RoundHole {
    /// What the group recorded for Wolf on the hole; nil when nothing is.
    var wolfEvent: Engine.WolfEvent? {
        let choice = wolfChoice.flatMap(Engine.WolfChoice.init(rawValue:))
        guard choice != nil || wolfPartnerID != nil || wolfPlayerID != nil else { return nil }
        return Engine.WolfEvent(choice: choice, partnerUserId: wolfPartnerID, wolfUserId: wolfPlayerID)
    }
}
