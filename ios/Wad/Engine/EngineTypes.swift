import Foundation

/// Inputs and outputs of the game engines. These mirror the TypeScript types in
/// backend/src/shared/types.ts and backend/src/engines; keep them in sync.
/// All money is integer cents.
enum Engine {
    typealias UserID = String
    typealias Cents = Int
    /// Net money change per player; positive = owed to them. Sums to zero.
    typealias Deltas = [UserID: Cents]
    /// Ticks received on each hole, keyed by hole number.
    typealias TicksByHole = [Int: Int]

    struct HoleInfo: Codable, Equatable, Sendable {
        /// 1-based hole number.
        var hole: Int
        var par: Int
        /// 1 = hardest hole on the course.
        var strokeIndex: Int
    }

    struct Player: Codable, Equatable, Sendable {
        var userId: UserID
        var displayName: String
        var courseHandicap: Int
    }

    /// Rating of a tee, for the course handicap. `par` is the tee's total par.
    struct TeeRating: Codable, Equatable, Sendable {
        var slope: Int
        var courseRating: Double
        var par: Int
    }

    struct Score: Codable, Equatable, Sendable {
        var userId: UserID
        var hole: Int
        var gross: Int
    }

    struct HoleEvents: Codable, Equatable, Sendable {
        var hole: Int
        /// Players whose first putt was holed from at least a flagstick's length, in the order made.
        var wadMakers: [UserID]
        /// Par 3s only; must have scored par or better.
        var greenieWinner: UserID?
        /// Wolf only; nil when nothing is recorded for the hole.
        var wolf: WolfEvent?

        init(hole: Int, wadMakers: [UserID] = [], greenieWinner: UserID? = nil, wolf: WolfEvent? = nil) {
            self.hole = hole
            self.wadMakers = wadMakers
            self.greenieWinner = greenieWinner
            self.wolf = wolf
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(hole, forKey: .hole)
            try container.encode(wadMakers, forKey: .wadMakers)
            // The TypeScript type is `UserId | null`, so nil is sent as null rather than omitted.
            try container.encode(greenieWinner, forKey: .greenieWinner)
            // `wolf?: WolfEvent`: absent when nothing is recorded.
            try container.encodeIfPresent(wolf, forKey: .wolf)
        }
    }

    /// What the group recorded for Wolf on a hole. The record can be wrong (a
    /// partner together with lone, say); the engine reports that, the type does
    /// not prevent it.
    struct WolfEvent: Codable, Equatable, Sendable {
        /// The Wolf takes one partner, or plays alone. Nil: not chosen yet.
        var choice: WolfChoice?
        /// The partner, with the choice `partner`.
        var partnerUserId: UserID?
        /// Who the Wolf is. Needed on holes 17 and 18 when players are tied for
        /// last place; elsewhere the engine derives the Wolf and checks this against it.
        var wolfUserId: UserID?

        init(choice: WolfChoice? = nil, partnerUserId: UserID? = nil, wolfUserId: UserID? = nil) {
            self.choice = choice
            self.partnerUserId = partnerUserId
            self.wolfUserId = wolfUserId
        }
    }

    enum WolfChoice: String, Codable, Sendable {
        case partner, lone
    }

    // MARK: Skins

    struct SkinsInput: Codable, Equatable, Sendable {
        var players: [Player]
        var holes: [HoleInfo]
        var scores: [Score]
        var baseCents: Cents
        /// Whether a pushed hole's value carries to the next hole. Nil is the
        /// engine's default, true.
        var carryover: Bool?
    }

    enum SkinStatus: String, Codable, Sendable {
        case won, pushed, pending
    }

    struct SkinHoleResult: Codable, Equatable, Sendable {
        var hole: Int
        var status: SkinStatus
        /// Value carried in from pushed holes. Nil when an earlier hole is pending.
        var carriedInCents: Cents?
        /// carriedIn + base. Nil when an earlier hole is pending.
        var atStakeCents: Cents?
        var winnerUserId: UserID?
        /// Net scores for the hole, present once every player has a score.
        var net: [UserID: Int]?
    }

    struct SkinsResult: Codable, Equatable, Sendable {
        var holes: [SkinHoleResult]
        var deltas: Deltas
        /// True when every hole has every player's score.
        var complete: Bool
        /// Value carried out of the last resolved hole (0 unless it was pushed). When
        /// `complete` is true and this is non-zero, the final carryover is unresolved:
        /// it is not paid out (Open Question 1 in docs/domain-model.md).
        var carryOutCents: Cents
    }

    // MARK: Wad

    struct WadInput: Codable, Equatable, Sendable {
        var players: [UserID]
        /// Holes 1-9 are the front instance, 10-18 the back.
        var holes: [HoleInfo]
        var scores: [Score]
        var holeEvents: [HoleEvents]
        var startCents: Cents
        var stepCents: Cents
    }

    enum WadSegment: String, Codable, Sendable {
        case front, back
    }

    struct WadMake: Codable, Equatable, Sendable {
        var hole: Int
        var userId: UserID
        /// Wad value after this make.
        var valueCents: Cents
    }

    struct WadInstanceResult: Codable, Equatable, Sendable {
        var segment: WadSegment
        var holderUserId: UserID?
        /// Current value: what the holder has, or what the first make would take.
        var valueCents: Cents
        var makes: [WadMake]
        /// Every player has a score on the segment's last hole; the holder has been paid.
        var complete: Bool
    }

    enum IgnoredMakeReason: String, Codable, Sendable {
        case notAPlayer = "not-a-player"
        case duplicate
    }

    struct IgnoredMake: Codable, Equatable, Sendable {
        var hole: Int
        var userId: UserID
        var reason: IgnoredMakeReason
    }

    struct WadResult: Codable, Equatable, Sendable {
        var instances: [WadInstanceResult]
        var deltas: Deltas
        var ignored: [IgnoredMake]
    }

    // MARK: Greenies

    struct GreeniesInput: Codable, Equatable, Sendable {
        var players: [UserID]
        var holes: [HoleInfo]
        var scores: [Score]
        var holeEvents: [HoleEvents]
        var amountCents: Cents
    }

    enum GreenieStatus: String, Codable, Sendable {
        case none, awarded, pending, invalid
    }

    struct GreenieHoleResult: Codable, Equatable, Sendable {
        var hole: Int
        var winnerUserId: UserID?
        var status: GreenieStatus
    }

    struct GreeniesResult: Codable, Equatable, Sendable {
        var holes: [GreenieHoleResult]
        var deltas: Deltas
    }

    // MARK: Wolf

    struct WolfInput: Codable, Equatable, Sendable {
        /// Exactly four.
        var players: [Player]
        /// The four players' ids in the order they tee off.
        var teeOrder: [UserID]
        /// Holes 1 to 18.
        var holes: [HoleInfo]
        var scores: [Score]
        var holeEvents: [HoleEvents]
        var pointCents: Cents
    }

    /// See backend/src/engines/wolf.ts. `needsWolf`: hole 17 or 18 with a tie
    /// for last place and no Wolf recorded; the engine does not pick (Open
    /// Question 4 in docs/domain-model.md).
    enum WolfHoleStatus: String, Codable, Sendable {
        case wonByWolfSide = "won_by_wolf_side"
        case wonByOpponents = "won_by_opponents"
        case tied, pending, invalid
        case needsWolf = "needs_wolf"
    }

    enum WolfInvalidReason: String, Codable, Sendable {
        case partnerAndLone = "partner_and_lone"
        case partnerMissing = "partner_missing"
        case partnerNotAPlayer = "partner_not_a_player"
        case wolfNotAPlayer = "wolf_not_a_player"
        case partnerIsWolf = "partner_is_wolf"
        case wolfContradictsRotation = "wolf_contradicts_rotation"
        case wolfNotInLastPlace = "wolf_not_in_last_place"
    }

    struct WolfHoleResult: Codable, Equatable, Sendable {
        var hole: Int
        /// Nil while the Wolf is not known: a pending hole 17 or 18, needs a
        /// Wolf, or a record that names no valid Wolf.
        var wolfUserId: UserID?
        var status: WolfHoleStatus
        /// Set only when the status is invalid.
        var invalidReason: WolfInvalidReason?
        /// The choice as recorded.
        var choice: WolfChoice?
        /// The partner as recorded.
        var partnerUserId: UserID?
        /// Holes 17 and 18 once the standings are known: the players in last place.
        var lastPlace: [UserID]?
        /// The Wolf, and the partner if there is one. Nil unless the hole is scored.
        var wolfSide: [UserID]?
        /// Everyone else, in tee order. Nil unless the hole is scored.
        var opponents: [UserID]?
        /// Lowest net score on each side. Nil unless the hole is scored.
        var wolfSideNet: Int?
        var opponentsNet: Int?
        /// Net scores for the hole, present once all four players have a score.
        var net: [UserID: Int]?
        /// Points awarded on this hole; all zero unless the hole was won.
        var points: [UserID: Int]
    }

    struct WolfResult: Codable, Equatable, Sendable {
        /// The tee order the rotation used.
        var teeOrder: [UserID]
        var holes: [WolfHoleResult]
        /// Running points per player, from scored holes only.
        var points: [UserID: Int]
        /// pointCents * (4 * own points - total points): every pair settles the difference in their points.
        var deltas: Deltas
        /// True when all 18 holes are won or tied.
        var complete: Bool
    }

    // MARK: Settlement

    struct Transfer: Codable, Equatable, Sendable {
        var from: UserID
        var to: UserID
        var amountCents: Cents
    }

    struct Settlement: Codable, Equatable, Sendable {
        var positions: Deltas
        var transfers: [Transfer]
    }
}
