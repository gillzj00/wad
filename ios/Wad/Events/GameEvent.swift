import Foundation

/// Something worth a show on the scoring phone. The raw value is the priority:
/// when one score triggers several events they play lowest value first, so a
/// hole in one that also wins the skin plays the hole in one, then the skin.
enum GameEventKind: Int, CaseIterable, Comparable, Hashable, Sendable {
    case holeInOne = 0
    /// Confirmed by the owner: a huge albatross takes the flag out of a storm.
    case albatross
    case eagle
    case greenie
    case wadTaken
    case skinWon
    case wolfHoleWon
    /// A gross score of exactly 8, by the owner's decision: 9 and worse get nothing.
    case snowman
    case birdie

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// How long the show runs before it moves on by itself.
    var duration: TimeInterval {
        switch self {
        case .holeInOne: 6
        case .albatross: 4
        case .greenie: 3.5
        case .eagle, .wadTaken, .wolfHoleWon, .snowman: 3
        case .skinWon, .birdie: 2.5
        }
    }

    /// The kind of event a gross score is, if any. Only the best one: a hole
    /// in one is not also an eagle.
    static func scoreEvent(gross: Int, par: Int) -> GameEventKind? {
        if gross == 1 { return .holeInOne }
        if gross == 8 { return .snowman }
        switch gross - par {
        case ...(-3): return .albatross
        case -2: return .eagle
        case -1: return .birdie
        default: return nil
        }
    }
}

/// An event of a round, identified by its kind, hole and players so that the
/// same event is recognised again after a correction elsewhere, whatever its
/// value has become.
struct GameEvent: Hashable, Sendable {
    struct Identity: Hashable, Sendable {
        var kind: GameEventKind
        var hole: Int
        var playerIDs: [String]
    }

    var kind: GameEventKind
    var hole: Int
    /// The player the event is about: the scorer, winner or maker. Two for a
    /// Wolf side.
    var playerIDs: [String]
    var playerNames: [String]
    /// Everybody else in the round, who a birdie is addressed to.
    var otherNames: [String] = []
    /// What the event is worth, when money is involved: the greenie amount,
    /// the Wad's value after the make, the skin's value.
    var amountCents: Int?

    var identity: Identity { Identity(kind: kind, hole: hole, playerIDs: playerIDs) }
}

/// The words on the screen during an event.
enum EventText {
    static func title(_ event: GameEvent) -> String {
        switch event.kind {
        case .holeInOne: "Hole in one"
        case .albatross: "Albatross"
        case .eagle: "Eagle"
        case .greenie: "Greenie"
        case .wadTaken: "Wad taken"
        case .skinWon: "Skin"
        case .wolfHoleWon: "Wolf"
        case .snowman: "Snowman"
        case .birdie: "Birdie"
        }
    }

    static func subtitle(_ event: GameEvent) -> String {
        let who = list(event.playerNames)
        let hole = "hole \(event.hole)"
        switch event.kind {
        case .holeInOne, .albatross, .eagle:
            return "\(who) on \(hole)"
        case .greenie:
            return "\(who) takes \(each(event.amountCents)) on \(hole)"
        case .wadTaken:
            if let amount = event.amountCents {
                return "\(who) holds the Wad at \(ScoringText.dollars(amount))"
            }
            return "\(who) holds the Wad"
        case .skinWon:
            return "\(who) takes \(each(event.amountCents)) on \(hole)"
        case .wolfHoleWon:
            return event.playerIDs.count == 1 ? "Lone Wolf \(who) takes \(hole)" : "\(who) take \(hole)"
        case .snowman:
            return "\(who) takes an 8 on \(hole)"
        case .birdie:
            return event.otherNames.isEmpty ? "From \(who)" : "From \(who) to \(list(event.otherNames))"
        }
    }

    private static func each(_ cents: Int?) -> String {
        guard let cents else { return "the pot" }
        return "\(ScoringText.dollars(cents)) a head"
    }

    /// "Zach", "Zach and Sam", "Zach, Sam and Alex".
    static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        }
    }
}
