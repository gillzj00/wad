import Foundation

enum WolfScoringError: Error, Equatable, Sendable {
    /// Wolf is not played in the round.
    case notPlayed
    /// The round has a score or a Wolf record, so the tee order cannot change.
    case teeOrderLocked
    /// The order is not the round's players, each once.
    case teeOrderNotThePlayers
}

/// The Wolf's choice on a hole as the group records it.
enum WolfChoiceRecord: Equatable, Sendable {
    case partner(String)
    case lone
}

/// Records the group's Wolf facts on a hole. The engine checks them: a record
/// that breaks a rule is reported there and never corrected here.
extension RoundScorer {
    /// Records the Wolf's choice, or clears it (nil). It can be corrected later.
    func setWolfChoice(_ choice: WolfChoiceRecord?, hole: Int) throws {
        let roundHole = try roundHole(hole)
        switch choice {
        case .partner(let partnerID):
            try requirePlayer(partnerID)
            roundHole.wolfChoice = Engine.WolfChoice.partner.rawValue
            roundHole.wolfPartnerID = partnerID
        case .lone:
            roundHole.wolfChoice = Engine.WolfChoice.lone.rawValue
            roundHole.wolfPartnerID = nil
        case nil:
            roundHole.wolfChoice = nil
            roundHole.wolfPartnerID = nil
        }
        try save()
    }

    /// Records who the Wolf is on the hole, or clears it (nil). Needed on holes
    /// 17 and 18 when players are tied for last place; the engine does not pick.
    func setWolf(_ playerID: String?, hole: Int) throws {
        let roundHole = try roundHole(hole)
        if let playerID { try requirePlayer(playerID) }
        roundHole.wolfPlayerID = playerID
        try save()
    }

    /// Sets the tee order, before play: the round has no score and no Wolf record.
    func setWolfTeeOrder(_ order: [String]) throws {
        guard round.playsWolf else { throw WolfScoringError.notPlayed }
        guard !round.isWolfTeeOrderLocked else { throw WolfScoringError.teeOrderLocked }
        let players = round.enginePlayerIDs
        guard order.count == players.count, Set(order) == Set(players) else {
            throw WolfScoringError.teeOrderNotThePlayers
        }
        round.wolfTeeOrderIDs = order
        try save()
    }

    /// Moves the player one place up (-1) or down (+1) in the tee order.
    func moveWolfTeeOrder(_ playerID: String, by offset: Int) throws {
        try setWolfTeeOrder(WolfTeeOrder.moving(playerID, by: offset, in: round.wolfTeeOrder))
    }
}
