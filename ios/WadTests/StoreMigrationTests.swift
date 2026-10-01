import Foundation
import SwiftData
import Testing
@testable import Wad

/// The models as they were before Venmo handles and paid markers were added
/// (commit 601ef1d): no `RoundPlayer.venmoHandle`, no `PaidMarker`, and no
/// `Round.startsEveryHoleAtPar`, which came later. The entity
/// names are the class names, so a store written with these is a store of the
/// previous version of the app.
enum PreviousSchema {
    static let models: [any PersistentModel.Type] = [Round.self, RoundHole.self, RoundPlayer.self, HoleScore.self]

    @Model
    final class Round {
        @Attribute(.unique) var id: UUID
        var courseName: String
        var startedAt: Date
        var courseRating: Double?
        var slope: Int?
        var wadStartCents: Int
        var wadStepCents: Int
        var skinsBaseCents: Int
        var greeniesAmountCents: Int

        @Relationship(deleteRule: .cascade, inverse: \RoundHole.round)
        var holes: [RoundHole] = []
        @Relationship(deleteRule: .cascade, inverse: \RoundPlayer.round)
        var players: [RoundPlayer] = []
        @Relationship(deleteRule: .cascade, inverse: \HoleScore.round)
        var scores: [HoleScore] = []

        init(id: UUID, courseName: String, startedAt: Date, courseRating: Double?, slope: Int?) {
            self.id = id
            self.courseName = courseName
            self.startedAt = startedAt
            self.courseRating = courseRating
            self.slope = slope
            wadStartCents = 700
            wadStepCents = 200
            skinsBaseCents = 500
            greeniesAmountCents = 500
        }
    }

    @Model
    final class RoundHole {
        var number: Int
        var par: Int
        var strokeIndex: Int
        var wadMakerIDs: [String] = []
        var greenieWinnerID: String?
        var round: Round?

        init(number: Int, par: Int, strokeIndex: Int) {
            self.number = number
            self.par = par
            self.strokeIndex = strokeIndex
        }
    }

    @Model
    final class RoundPlayer {
        var playerID: String
        var displayName: String
        var position: Int
        var handicapIndex: Double?
        var courseHandicap: Int
        var round: Round?

        init(playerID: String, displayName: String, position: Int, handicapIndex: Double?, courseHandicap: Int) {
            self.playerID = playerID
            self.displayName = displayName
            self.position = position
            self.handicapIndex = handicapIndex
            self.courseHandicap = courseHandicap
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
}

/// A store written by the previous version of the app opens with this one, and
/// the rounds in it are all there.
@MainActor
struct StoreMigrationTests {
    let directory: URL
    let storeURL: URL
    let roundID = UUID()
    let startedAt = Date(timeIntervalSince1970: 1_790_424_000)

    init() throws {
        directory = URL.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storeURL = directory.appending(path: "previous.store")
    }

    /// The finished round of `DebugRounds.finalPush`, written with the previous models.
    private func writePreviousStore() throws {
        let schema = Schema(PreviousSchema.models)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: storeURL))
        let context = ModelContext(container)

        let round = PreviousSchema.Round(
            id: roundID,
            courseName: "Carryover Links",
            startedAt: startedAt,
            courseRating: nil,
            slope: nil
        )
        context.insert(round)
        round.holes = zip(RoundFixtures.pars, RoundFixtures.strokeIndexes).enumerated().map { offset, hole in
            PreviousSchema.RoundHole(number: offset + 1, par: hole.0, strokeIndex: hole.1)
        }
        let players = [("zach", "Zach", 15), ("sam", "Sam", 7), ("alex", "Alex", 7)]
        round.players = players.enumerated().map { offset, player in
            PreviousSchema.RoundPlayer(
                playerID: player.0,
                displayName: player.1,
                position: offset,
                handicapIndex: nil,
                courseHandicap: player.2
            )
        }
        for hole in round.holes {
            for player in players {
                let gross = player.0 == "zach" && hole.number == 17 ? 5 : hole.par
                round.scores.append(PreviousSchema.HoleScore(playerID: player.0, hole: hole.number, gross: gross))
            }
        }
        round.holes.first { $0.number == 2 }?.wadMakerIDs = ["sam"]
        round.holes.first { $0.number == 3 }?.greenieWinnerID = "alex"
        try context.save()
    }

    @Test func aStoreOfThePreviousVersionOpensWithItsRounds() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePreviousStore()

        // The way the app opens its store (WadApp): with the course cache, which the previous version did not have.
        let container = try ModelContainer(for: Schema(WadSchema.models), configurations: ModelConfiguration(url: storeURL))
        let context = container.mainContext
        let rounds = try context.fetch(FetchDescriptor<Round>())
        #expect(rounds.count == 1)
        let round = try #require(rounds.first)

        #expect(round.id == roundID)
        #expect(round.courseName == "Carryover Links")
        #expect(round.startedAt == startedAt)
        #expect(round.settings == .defaults)
        #expect(round.orderedHoles.map(\.par) == RoundFixtures.pars)
        #expect(round.orderedHoles.map(\.strokeIndex) == RoundFixtures.strokeIndexes)
        #expect(round.hole(2)?.wadMakerIDs == ["sam"])
        #expect(round.hole(3)?.greenieWinnerID == "alex")
        #expect(round.orderedPlayers.map(\.displayName) == ["Zach", "Sam", "Alex"])
        #expect(round.orderedPlayers.map(\.courseHandicap) == [15, 7, 7])
        #expect(round.scores.count == 54)
        #expect(round.gross(playerID: "zach", hole: 17) == 5)

        // What is new starts empty.
        #expect(round.orderedPlayers.map(\.venmoHandle) == [nil, nil, nil])
        #expect(round.paidMarkers.isEmpty)
        #expect(round.startsEveryHoleAtPar == false)

        // The round settles as before and takes what is new.
        let bridge = try EngineBridge()
        let settlement = try RoundSettlement(round: round, bridge: bridge)
        #expect(settlement.payments.map(\.amountCents) == [6700, 6100])
        let ledger = PaymentLedger(round: round)
        try ledger.setVenmoHandle("@zach-golf", playerID: "zach")
        try ledger.markPaid(try #require(settlement.payments.first), in: settlement, at: startedAt)

        let reread = try #require(try ModelContext(container).fetch(FetchDescriptor<Round>()).first)
        #expect(reread.orderedPlayers.map(\.venmoHandle) == ["zach-golf", nil, nil])
        #expect(reread.paidRecords == [PaidRecord(payerID: "alex", payeeID: "zach", amountCents: 6700, paidAt: startedAt)])
        #expect(reread.scores.count == 54)
    }

    /// A round from before Wolf does not play it, and the Wolf fields added to
    /// the round and its holes can be written to the migrated store.
    @Test func aStoreOfThePreviousVersionHasNoWolfAndTakesIt() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePreviousStore()

        let container = try ModelContainer(for: Schema(WadSchema.models), configurations: ModelConfiguration(url: storeURL))
        let round = try #require(try container.mainContext.fetch(FetchDescriptor<Round>()).first)
        #expect(round.playsWolf == false)
        #expect(round.wolfPointCents == nil)
        #expect(round.wolfTeeOrderIDs.isEmpty)
        #expect(round.wolfTeeOrder == ["zach", "sam", "alex"])
        #expect(round.wolfInput == nil)
        #expect(round.orderedHoles.allSatisfy { $0.wolfChoice == nil && $0.wolfPartnerID == nil && $0.wolfPlayerID == nil })
        #expect(round.orderedHoles.allSatisfy { $0.wolfEvent == nil })
        let bridge = try EngineBridge()
        #expect(try RoundStatus(round: round, bridge: bridge).wolf == nil)
        #expect(try RoundSettlement(round: round, bridge: bridge).isFinal)

        // The migrated store takes the new fields.
        round.wolfPointCents = 100
        round.wolfTeeOrderIDs = ["sam", "zach", "alex"]
        round.hole(17)?.wolfChoice = "partner"
        round.hole(17)?.wolfPartnerID = "sam"
        round.hole(17)?.wolfPlayerID = "zach"
        try container.mainContext.save()

        let reread = try #require(try ModelContext(container).fetch(FetchDescriptor<Round>()).first)
        #expect(reread.wolfPointCents == 100)
        #expect(reread.wolfTeeOrder == ["sam", "zach", "alex"])
        #expect(reread.hole(17)?.wolfEvent == Engine.WolfEvent(choice: .partner, partnerUserId: "sam", wolfUserId: "zach"))
        #expect(reread.hole(16)?.wolfEvent == nil)
        // Three players: Wolf is on and unavailable, and the round still settles.
        let settlement = try RoundSettlement(round: reread, bridge: bridge)
        #expect(settlement.isWolfUnavailable)
        #expect(settlement.payments.map(\.amountCents) == [6700, 6100])
    }
}
