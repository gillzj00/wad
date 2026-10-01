import Foundation
import SwiftData

enum ScoringError: Error, Equatable, Sendable {
    case unknownHole(Int)
    case unknownPlayer(String)
    case grossOutOfRange(Int)
    case greenieNotOnPar3(hole: Int)
    /// The player has no score of par or better on the hole.
    case greenieNotEligible(playerID: String, hole: Int)
}

/// Records what happened on a hole: gross scores, the ordered Wad makers and
/// the greenie winner. Every change is saved straight away, so quitting the app
/// mid-round loses nothing. No game math happens here; see `RoundStatus`.
@MainActor
struct RoundScorer {
    static let grossRange = 1...20

    let round: Round

    // MARK: Gross scores

    /// Sets or clears (nil) a player's gross score on a hole.
    func setGross(_ gross: Int?, playerID: String, hole: Int) throws {
        _ = try roundHole(hole)
        try requirePlayer(playerID)
        if let gross, !Self.grossRange.contains(gross) { throw ScoringError.grossOutOfRange(gross) }
        round.setGross(gross, playerID: playerID, hole: hole)
        try save()
    }

    /// One tap of the stepper. An unset score starts at par whatever the
    /// direction; a set score moves by `delta` and stays within `grossRange`.
    func stepGross(by delta: Int, playerID: String, hole: Int) throws {
        let par = try roundHole(hole).par
        guard let current = round.gross(playerID: playerID, hole: hole) else {
            try setGross(par, playerID: playerID, hole: hole)
            return
        }
        let next = min(max(current + delta, Self.grossRange.lowerBound), Self.grossRange.upperBound)
        try setGross(next, playerID: playerID, hole: hole)
    }

    /// Gives par to every player without a score on the hole.
    func setParForUnscored(hole: Int) throws {
        let par = try roundHole(hole).par
        for player in round.orderedPlayers where round.gross(playerID: player.playerID, hole: hole) == nil {
            round.setGross(par, playerID: player.playerID, hole: hole)
        }
        try save()
    }

    // MARK: Wad

    /// Player ids whose first putt qualified on the hole, in the order made.
    func wadMakers(hole: Int) -> [String] {
        round.hole(hole)?.wadMakerIDs ?? []
    }

    /// 1-based place of the player among the hole's makers, nil if not a maker.
    func wadOrder(playerID: String, hole: Int) -> Int? {
        wadMakers(hole: hole).firstIndex(of: playerID).map { $0 + 1 }
    }

    /// Adds the player after the makers already recorded. A player qualifies at
    /// most once per hole, so adding a maker again changes nothing and returns false.
    @discardableResult
    func addWadMaker(playerID: String, hole: Int) throws -> Bool {
        let roundHole = try roundHole(hole)
        try requirePlayer(playerID)
        guard !roundHole.wadMakerIDs.contains(playerID) else { return false }
        roundHole.wadMakerIDs = roundHole.wadMakerIDs + [playerID]
        try save()
        return true
    }

    func removeWadMaker(playerID: String, hole: Int) throws {
        let roundHole = try roundHole(hole)
        roundHole.wadMakerIDs = roundHole.wadMakerIDs.filter { $0 != playerID }
        try save()
    }

    /// Removes the player if recorded, otherwise adds them last.
    func toggleWadMaker(playerID: String, hole: Int) throws {
        if wadMakers(hole: hole).contains(playerID) {
            try removeWadMaker(playerID: playerID, hole: hole)
        } else {
            try addWadMaker(playerID: playerID, hole: hole)
        }
    }

    // MARK: Greenies

    /// The players who can be offered as the greenie winner: a par 3, and a
    /// gross score of par or better on it.
    func greenieCandidates(hole: Int) -> [RoundPlayer] {
        guard let roundHole = round.hole(hole), roundHole.par == 3 else { return [] }
        return round.orderedPlayers.filter {
            guard let gross = round.gross(playerID: $0.playerID, hole: hole) else { return false }
            return gross <= roundHole.par
        }
    }

    /// Records the greenie winner, or none (nil). Rejects a player who is not a candidate.
    func setGreenieWinner(_ playerID: String?, hole: Int) throws {
        let roundHole = try roundHole(hole)
        if let playerID {
            try requirePlayer(playerID)
            guard roundHole.par == 3 else { throw ScoringError.greenieNotOnPar3(hole: hole) }
            guard greenieCandidates(hole: hole).contains(where: { $0.playerID == playerID }) else {
                throw ScoringError.greenieNotEligible(playerID: playerID, hole: hole)
            }
        }
        roundHole.greenieWinnerID = playerID
        try save()
    }

    // MARK: Shared with the Wolf records (RoundScorer+Wolf.swift)

    func roundHole(_ number: Int) throws -> RoundHole {
        guard let hole = round.hole(number) else { throw ScoringError.unknownHole(number) }
        return hole
    }

    func requirePlayer(_ playerID: String) throws {
        guard round.players.contains(where: { $0.playerID == playerID }) else {
            throw ScoringError.unknownPlayer(playerID)
        }
    }

    func save() throws {
        try round.modelContext?.save()
    }
}
