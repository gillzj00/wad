import Foundation

/// The state of every game for a round, scored by the engines from what has
/// been recorded so far. Nothing here is computed in Swift.
struct RoundStatus: Equatable, Sendable {
    /// Skins ticks per player id, then per hole number: only the players in
    /// Skins, and nobody when Skins is not played.
    var ticks: [Engine.UserID: Engine.TicksByHole]
    var skins: Engine.SkinsResult
    var wad: Engine.WadResult
    var greenies: Engine.GreeniesResult
    /// Nil when Wolf is not played, or unavailable (not exactly four players).
    var wolf: Engine.WolfResult?

    @MainActor
    init(round: Round, bridge: EngineBridge) throws {
        // A game with fewer than two players in is not played: its engine does
        // not run and its empty result moves no money.
        ticks = try round.skinsTicks(using: bridge)
        skins = round.isPlayed(.skins) ? try bridge.scoreSkins(round.skinsInput) : Self.notPlayedSkins
        wad = round.isPlayed(.wad) ? try bridge.scoreWad(round.wadInput) : Self.notPlayedWad
        greenies = round.isPlayed(.greenies) ? try bridge.scoreGreenies(round.greeniesInput) : Self.notPlayedGreenies
        wolf = try round.wolfInput.flatMap(bridge.scoreWolf)
    }

    static let notPlayedSkins = Engine.SkinsResult(holes: [], deltas: [:], complete: false, carryOutCents: 0)
    static let notPlayedWad = Engine.WadResult(instances: [], deltas: [:], ignored: [])
    static let notPlayedGreenies = Engine.GreeniesResult(holes: [], deltas: [:])

    /// Per-game deltas in the order skins, wad, greenies, then Wolf when it is
    /// played: the input of `EngineBridge.settle`.
    var gameDeltas: [Engine.Deltas] {
        [skins.deltas, wad.deltas, greenies.deltas] + (wolf.map { [$0.deltas] } ?? [])
    }

    func ticks(playerID: String, hole: Int) -> Int? {
        ticks[playerID]?[hole]
    }

    /// The engine's net score. Nil until every player has a score on the hole.
    func net(playerID: String, hole: Int) -> Int? {
        skinsHole(hole)?.net?[playerID]
    }

    func skinsHole(_ hole: Int) -> Engine.SkinHoleResult? {
        skins.holes.first { $0.hole == hole }
    }

    /// The Wad instance of the nine the hole is in.
    func wadInstance(hole: Int) -> Engine.WadInstanceResult? {
        let segment: Engine.WadSegment = hole <= 9 ? .front : .back
        return wad.instances.first { $0.segment == segment }
    }

    /// The makes the engine counted on the hole, in order, with the value after each.
    func wadMakes(hole: Int) -> [Engine.WadMake] {
        wadInstance(hole: hole)?.makes.filter { $0.hole == hole } ?? []
    }

    /// Nil on a hole that is not a par 3 and has no greenie recorded.
    func greenieHole(_ hole: Int) -> Engine.GreenieHoleResult? {
        greenies.holes.first { $0.hole == hole }
    }

    /// Holes whose recorded greenie winner the engine refuses to pay.
    var invalidGreenieHoles: [Int] {
        greenies.holes.filter { $0.status == .invalid }.map(\.hole)
    }
}
