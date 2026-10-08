import Foundation
import SwiftData

/// Local copy of a round: a snapshot of the course, the players with the
/// handicaps used for the round, the game settings and the per-hole results.
/// The offline-first store is the working copy during play
/// (docs/architecture.md). Rounds are always 18 holes. All money is integer cents.
@Model
final class Round {
    @Attribute(.unique) var id: UUID
    var courseName: String
    var startedAt: Date

    /// Tee course rating and slope. Both are set or both are nil.
    var courseRating: Double?
    var slope: Int?

    var wadStartCents: Int
    var wadStepCents: Int
    var skinsBaseCents: Int
    var greeniesAmountCents: Int

    /// A pushed skins hole adds its value to the next hole. Off, a push pays
    /// nothing and the next hole is worth the base again. Rounds from before
    /// this setting exists read true, the only way skins was played.
    var skinsCarryover: Bool = true

    /// Wolf's value per point; nil when Wolf is not played. Rounds from before
    /// Wolf read nil. See `Round+Wolf.swift`.
    var wolfPointCents: Int?
    /// The players' ids in the order they tee off for Wolf. Use `wolfTeeOrder`,
    /// which fills in players that are missing from it.
    var wolfTeeOrderIDs: [String] = []

    /// The code the round was last shared live under (`LiveCode`), so that
    /// sharing it again gives the followers the same code. Nil until shared;
    /// rounds from before live sharing read nil.
    var liveCode: String?

    /// Unordered in the store; use `orderedHoles`.
    @Relationship(deleteRule: .cascade, inverse: \RoundHole.round)
    var holes: [RoundHole] = []

    /// Unordered in the store; use `orderedPlayers`.
    @Relationship(deleteRule: .cascade, inverse: \RoundPlayer.round)
    var players: [RoundPlayer] = []

    /// Gross scores entered so far, at most one per player per hole.
    @Relationship(deleteRule: .cascade, inverse: \HoleScore.round)
    var scores: [HoleScore] = []

    /// Payments the group has marked paid. See `PaymentLedger`.
    @Relationship(deleteRule: .cascade, inverse: \PaidMarker.round)
    var paidMarkers: [PaidMarker] = []

    init(
        id: UUID = UUID(),
        courseName: String,
        startedAt: Date = .now,
        courseRating: Double? = nil,
        slope: Int? = nil,
        settings: GameSettings = .defaults,
        skinsCarryover: Bool = true
    ) {
        self.id = id
        self.courseName = courseName
        self.startedAt = startedAt
        self.courseRating = courseRating
        self.slope = slope
        self.wadStartCents = settings.wadStartCents
        self.wadStepCents = settings.wadStepCents
        self.skinsBaseCents = settings.skinsBaseCents
        self.greeniesAmountCents = settings.greeniesAmountCents
        self.skinsCarryover = skinsCarryover
    }

    var orderedHoles: [RoundHole] {
        holes.sorted { $0.number < $1.number }
    }

    var orderedPlayers: [RoundPlayer] {
        players.sorted { $0.position < $1.position }
    }

    var totalPar: Int {
        holes.reduce(0) { $0 + $1.par }
    }

    var settings: GameSettings {
        GameSettings(
            wadStartCents: wadStartCents,
            wadStepCents: wadStepCents,
            skinsBaseCents: skinsBaseCents,
            greeniesAmountCents: greeniesAmountCents
        )
    }

    func hole(_ number: Int) -> RoundHole? {
        holes.first { $0.number == number }
    }

    func gross(playerID: String, hole: Int) -> Int? {
        scores.first { $0.playerID == playerID && $0.hole == hole }?.gross
    }

    /// Sets or clears (nil) a player's gross score on a hole.
    func setGross(_ gross: Int?, playerID: String, hole: Int) {
        let existing = scores.first { $0.playerID == playerID && $0.hole == hole }
        guard let gross else {
            if let existing {
                scores.removeAll { $0 === existing }
                existing.modelContext?.delete(existing)
            }
            return
        }
        if let existing {
            existing.gross = gross
        } else {
            scores.append(HoleScore(playerID: playerID, hole: hole, gross: gross))
        }
    }
}

/// One hole of the round's course snapshot, with the events recorded on it.
@Model
final class RoundHole {
    /// 1-based hole number.
    var number: Int
    /// 3 to 5.
    var par: Int
    /// 1 to 18; 1 is the hardest hole.
    var strokeIndex: Int
    /// Player ids whose first putt qualified for the Wad, in the order made.
    var wadMakerIDs: [String] = []
    /// Par 3s only.
    var greenieWinnerID: String?
    /// Wolf: "partner" or "lone" as the group recorded it; nil until chosen.
    var wolfChoice: String?
    /// Wolf: the partner, with the choice "partner".
    var wolfPartnerID: String?
    /// Wolf: who the Wolf is, recorded on holes 17 and 18 when players are
    /// tied for last place (Open Question 4 in docs/domain-model.md).
    var wolfPlayerID: String?
    var round: Round?

    init(number: Int, par: Int, strokeIndex: Int) {
        self.number = number
        self.par = par
        self.strokeIndex = strokeIndex
    }
}

@Model
final class RoundPlayer {
    /// Stable id, used as the engine's userId.
    var playerID: String
    var displayName: String
    /// Order the player was added in.
    var position: Int
    /// Nil when the handicap was entered directly as a course handicap.
    var handicapIndex: Double?
    /// The handicap used for this round: computed from the index and the tee, or entered by the group.
    var courseHandicap: Int
    /// Venmo username without the "@". Optional.
    var venmoHandle: String?
    var round: Round?

    init(
        playerID: String = UUID().uuidString,
        displayName: String,
        position: Int,
        handicapIndex: Double? = nil,
        courseHandicap: Int,
        venmoHandle: String? = nil
    ) {
        self.playerID = playerID
        self.displayName = displayName
        self.position = position
        self.handicapIndex = handicapIndex
        self.courseHandicap = courseHandicap
        self.venmoHandle = venmoHandle
    }
}

/// The group marked a payment as made: who paid whom, how much and when. It
/// belongs to the transfer with the same payer, payee and amount, like the
/// backend's transfer id (docs/api.md, Settlement), and to no other.
@Model
final class PaidMarker {
    var payerID: String
    var payeeID: String
    var amountCents: Int
    var paidAt: Date
    var round: Round?

    init(payerID: String, payeeID: String, amountCents: Int, paidAt: Date) {
        self.payerID = payerID
        self.payeeID = payeeID
        self.amountCents = amountCents
        self.paidAt = paidAt
    }
}

@Model
final class HoleScore {
    var playerID: String
    var hole: Int
    var gross: Int
    var round: Round?

    init(playerID: String, hole: Int, gross: Int) {
        self.playerID = playerID
        self.hole = hole
        self.gross = gross
    }
}

/// Game amounts for a round, in integer cents.
struct GameSettings: Equatable, Sendable {
    var wadStartCents: Int
    var wadStepCents: Int
    var skinsBaseCents: Int
    var greeniesAmountCents: Int

    /// Defaults from docs/domain-model.md.
    static let defaults = GameSettings(
        wadStartCents: 700,
        wadStepCents: 200,
        skinsBaseCents: 500,
        greeniesAmountCents: 500
    )
}
