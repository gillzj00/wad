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

        init(hole: Int, wadMakers: [UserID] = [], greenieWinner: UserID? = nil) {
            self.hole = hole
            self.wadMakers = wadMakers
            self.greenieWinner = greenieWinner
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(hole, forKey: .hole)
            try container.encode(wadMakers, forKey: .wadMakers)
            // The TypeScript type is `UserId | null`, so nil is sent as null rather than omitted.
            try container.encode(greenieWinner, forKey: .greenieWinner)
        }
    }

    // MARK: Skins

    struct SkinsInput: Codable, Equatable, Sendable {
        var players: [Player]
        var holes: [HoleInfo]
        var scores: [Score]
        var baseCents: Cents
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
