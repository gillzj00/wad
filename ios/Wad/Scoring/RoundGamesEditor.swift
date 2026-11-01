import Foundation
import SwiftData

/// Who is in each side game and the skins carryover, as the Games sheet
/// edits them before they are saved.
struct RoundGames: Equatable, Sendable {
    struct Player: Equatable, Identifiable, Sendable {
        var id: String
        var name: String
        var playsSkins: Bool
        var playsWad: Bool
        var playsGreenies: Bool

        func plays(_ game: SideGame) -> Bool {
            switch game {
            case .skins: playsSkins
            case .wad: playsWad
            case .greenies: playsGreenies
            }
        }

        mutating func setPlays(_ game: SideGame, _ plays: Bool) {
            switch game {
            case .skins: playsSkins = plays
            case .wad: playsWad = plays
            case .greenies: playsGreenies = plays
            }
        }
    }

    /// In the order the players were added.
    var players: [Player]
    var skinsCarryover: Bool

    @MainActor
    init(round: Round) {
        players = round.orderedPlayers.map {
            Player(
                id: $0.playerID,
                name: $0.displayName,
                playsSkins: $0.playsSkins,
                playsWad: $0.playsWad,
                playsGreenies: $0.playsGreenies
            )
        }
        skinsCarryover = round.skinsCarryover
    }

    func isPlayed(_ game: SideGame) -> Bool {
        players.filter { $0.plays(game) }.count >= SideGame.minimumPlayers
    }
}

/// What saving the games removes from one player: their greenie wins when
/// they leave Greenies and their Wad makes when they leave Wad.
struct GamesRemoval: Equatable, Sendable {
    var playerID: String
    var name: String
    var greenieHoles: [Int]
    var wadHoles: [Int]

    /// "Jo's greenie on hole 3 and Wad makes on holes 4 and 12 will be removed."
    var sentence: String {
        var items: [String] = []
        if !greenieHoles.isEmpty {
            items.append("\(greenieHoles.count == 1 ? "greenie" : "greenies") on \(Self.holes(greenieHoles))")
        }
        if !wadHoles.isEmpty {
            items.append("\(wadHoles.count == 1 ? "Wad make" : "Wad makes") on \(Self.holes(wadHoles))")
        }
        return "\(name)'s \(items.joined(separator: " and ")) will be removed."
    }

    /// "hole 3", "holes 4 and 12", "holes 4, 7 and 12".
    static func holes(_ numbers: [Int]) -> String {
        let texts = numbers.map(String.init)
        guard let last = texts.last else { return "" }
        if texts.count == 1 { return "hole \(last)" }
        return "holes \(texts.dropLast().joined(separator: ", ")) and \(last)"
    }
}

/// Changes who is in each side game and the skins carryover of an existing
/// round, at any time. A player taken out of a game loses what was recorded
/// for them in it: their greenie wins in Greenies, their Wad makes in Wad;
/// nothing is recorded per player in Skins. Putting a player back in restores
/// nothing. Everything that reads the round recomputes from it, so nothing
/// else changes here, and no show is played (docs/domain-model.md, Participation).
@MainActor
struct RoundGamesEditor {
    let round: Round

    /// What saving `games` would remove, by player in order; empty when nothing.
    func removals(for games: RoundGames) -> [GamesRemoval] {
        let holes = round.orderedHoles
        return games.players.compactMap { player in
            let greenies = player.playsGreenies
                ? [] : holes.filter { $0.greenieWinnerID == player.id }.map(\.number)
            let wad = player.playsWad
                ? [] : holes.filter { $0.wadMakerIDs.contains(player.id) }.map(\.number)
            guard !greenies.isEmpty || !wad.isEmpty else { return nil }
            return GamesRemoval(playerID: player.id, name: player.name, greenieHoles: greenies, wadHoles: wad)
        }
    }

    /// Saves the participation and the carryover, and removes what `removals` lists, in one save.
    func apply(_ games: RoundGames) throws {
        let removals = removals(for: games)
        for player in round.players {
            guard let choice = games.players.first(where: { $0.id == player.playerID }) else { continue }
            for game in SideGame.allCases where player.plays(game) != choice.plays(game) {
                switch game {
                case .skins: player.playsSkins = choice.playsSkins
                case .wad: player.playsWad = choice.playsWad
                case .greenies: player.playsGreenies = choice.playsGreenies
                }
            }
        }
        if round.skinsCarryover != games.skinsCarryover {
            round.skinsCarryover = games.skinsCarryover
        }
        for removal in removals {
            for hole in round.holes {
                if removal.greenieHoles.contains(hole.number), hole.greenieWinnerID == removal.playerID {
                    hole.greenieWinnerID = nil
                }
                if removal.wadHoles.contains(hole.number) {
                    hole.wadMakerIDs = hole.wadMakerIDs.filter { $0 != removal.playerID }
                }
            }
        }
        try RoundScorer(round: round).save()
    }
}
