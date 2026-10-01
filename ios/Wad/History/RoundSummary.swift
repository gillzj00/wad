import Foundation
import Observation

/// What a row of the round history says about a round. Every amount is taken
/// from the settlement as the engines computed it.
struct RoundSummary: Equatable, Sendable {
    enum Progress: Equatable, Sendable {
        case notStarted
        /// `inOrder`: the holes scored are the first ones of the round.
        case inProgress(completed: Int, total: Int, inOrder: Bool)
        /// Every score is in, and a Wolf hole is not scored (needs a Wolf, no choice, or invalid).
        case wolfUnfinished
        case final
    }

    enum Settled: Equatable, Sendable {
        /// The final settlement has no payments.
        case nothingOwed
        case unsettled(paid: Int, total: Int)
        case allSettled
        /// A recorded greenie is not paid, so nothing can be paid yet.
        case needsFixing
    }

    var progress: Progress
    /// The players with the best result and what they won. Final rounds only.
    var headline: String?
    /// Final rounds only.
    var settled: Settled?

    init(settlement: RoundSettlement, payments: PaymentStatus) {
        guard settlement.isFinal else {
            let completed = settlement.completedHoleCount
            progress = if settlement.incompleteHoles.isEmpty {
                .wolfUnfinished
            } else if completed == 0 {
                .notStarted
            } else {
                .inProgress(
                    completed: completed,
                    total: settlement.holeNumbers.count,
                    inOrder: settlement.isScoredInOrder
                )
            }
            return
        }
        progress = .final
        headline = Self.headline(settlement)
        if !payments.isReadyForPayment {
            settled = .needsFixing
        } else if payments.transfers.isEmpty {
            settled = .nothingOwed
        } else if payments.isAllSettled {
            settled = .allSettled
        } else {
            settled = .unsettled(paid: payments.paidCount, total: payments.transfers.count)
        }
    }

    private static func headline(_ settlement: RoundSettlement) -> String {
        guard let best = settlement.players.map(\.netCents).max(), best > 0 else { return "All even" }
        let winners = settlement.players.filter { $0.netCents == best }.map(\.name)
        return "\(winners.joined(separator: " and ")) won \(ScoringText.dollars(best))"
    }

    /// "In progress, through 7 holes" or "Final: Zach won $128.00".
    var progressText: String {
        switch progress {
        case .notStarted:
            "Not started"
        case .inProgress(let completed, let total, let inOrder):
            inOrder
                ? "In progress, through \(completed) \(completed == 1 ? "hole" : "holes")"
                : "In progress, \(completed) of \(total) holes scored"
        case .wolfUnfinished:
            "Not final: a Wolf hole is not scored"
        case .final:
            "Final" + (headline.map { ": " + $0 } ?? "")
        }
    }

    var settledText: String? {
        switch settled {
        case nil: nil
        case .nothingOwed: "Nobody owes anything"
        case .allSettled: "All settled"
        case .needsFixing: "Not settled: a greenie needs fixing"
        case .unsettled(let paid, let total):
            paid == 0
                ? "Not settled: \(total) \(total == 1 ? "payment" : "payments") to make"
                : "Not settled: \(paid) of \(total) payments paid"
        }
    }
}

/// Everything a round's summary depends on. A summary is computed again only
/// when this changes.
struct RoundSummaryKey: Equatable, Sendable {
    var skins: Engine.SkinsInput
    var wad: Engine.WadInput
    var greenies: Engine.GreeniesInput
    var wolf: Engine.WolfInput?
    var paid: [PaidRecord]

    @MainActor
    init(round: Round) {
        skins = round.skinsInput
        wad = round.wadInput
        greenies = round.greeniesInput
        wolf = round.wolfInput
        paid = round.paidRecords
    }
}

/// Summaries of the rounds in the history, kept in memory so that the engines
/// run once per change of a round and not for every row on every render.
@MainActor
@Observable
final class RoundSummaryCache {
    private struct Entry {
        var key: RoundSummaryKey
        /// Nil when the engines failed.
        var summary: RoundSummary?
    }

    private var entries: [UUID: Entry] = [:]
    /// How many times the engines ran, for the tests.
    @ObservationIgnored private(set) var computations = 0

    /// The summary computed for the round as it is now, if there is one.
    func summary(for round: Round, key: RoundSummaryKey) -> RoundSummary? {
        guard let entry = entries[round.id], entry.key == key else { return nil }
        return entry.summary
    }

    /// The last summary computed for the round, which may be out of date. Shown
    /// while the new one is computed, so that a row does not flicker.
    func lastSummary(for round: Round) -> RoundSummary? {
        entries[round.id]?.summary
    }

    /// Computes the summary unless the one in the cache is current.
    func refresh(_ round: Round, key: RoundSummaryKey, bridge: EngineBridge?) {
        if let entry = entries[round.id], entry.key == key { return }
        computations += 1
        let summary: RoundSummary? = bridge.flatMap { bridge in
            guard let settlement = try? RoundSettlement(round: round, bridge: bridge) else { return nil }
            return RoundSummary(
                settlement: settlement,
                payments: PaymentStatus(settlement: settlement, records: key.paid)
            )
        }
        entries[round.id] = Entry(key: key, summary: summary)
    }

    func remove(_ roundID: UUID) {
        entries[roundID] = nil
    }
}
