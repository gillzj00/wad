import Foundation
import SwiftData

enum PaymentError: Error, Equatable, Sendable {
    /// Holes are missing scores (the backend's `round_incomplete`).
    case roundIncomplete
    /// A recorded greenie is not paid (the backend's `settlement_has_issues`).
    case settlementHasIssues
    /// Not a payment of the current settlement (the backend's `transfer_not_found`).
    case notATransfer
    case unknownPlayer(String)
    case invalidVenmoHandle
}

extension Round {
    /// Oldest first.
    var paidRecords: [PaidRecord] {
        paidMarkers
            .map { PaidRecord(payerID: $0.payerID, payeeID: $0.payeeID, amountCents: $0.amountCents, paidAt: $0.paidAt) }
            .sorted { ($0.paidAt, $0.payerID, $0.payeeID, $0.amountCents) < ($1.paidAt, $1.payerID, $1.payeeID, $1.amountCents) }
    }
}

/// Records which payments the group marked paid, and the players' Venmo
/// handles. Every change is saved straight away. The app never moves money:
/// a marker only says that the group told the app a payment was made.
@MainActor
struct PaymentLedger {
    let round: Round

    /// Marks a payment of the settlement paid. Needs a settlement that is ready
    /// for payment. Marking a paid transfer again keeps the first date.
    func markPaid(_ payment: RoundSettlement.Payment, in settlement: RoundSettlement, at date: Date = .now) throws {
        guard settlement.isFinal else { throw PaymentError.roundIncomplete }
        guard settlement.isReadyForPayment else { throw PaymentError.settlementHasIssues }
        guard settlement.payments.contains(payment) else { throw PaymentError.notATransfer }
        guard !round.paidRecords.contains(where: { $0.matches(payment) }) else { return }
        round.paidMarkers.append(
            PaidMarker(payerID: payment.fromID, payeeID: payment.toID, amountCents: payment.amountCents, paidAt: date)
        )
        try save()
    }

    /// Removes the marker of a transfer. Always allowed.
    func markUnpaid(_ payment: RoundSettlement.Payment) throws {
        try removeMarkers { $0.payerID == payment.fromID && $0.payeeID == payment.toID && $0.amountCents == payment.amountCents }
    }

    /// Removes a marker that matches no transfer any more.
    func removeStale(_ record: PaidRecord) throws {
        try removeMarkers {
            $0.payerID == record.payerID && $0.payeeID == record.payeeID
                && $0.amountCents == record.amountCents && $0.paidAt == record.paidAt
        }
    }

    /// Sets the player's Venmo handle from what was typed; nothing typed clears it.
    func setVenmoHandle(_ text: String, playerID: String) throws {
        guard let player = round.players.first(where: { $0.playerID == playerID }) else {
            throw PaymentError.unknownPlayer(playerID)
        }
        switch VenmoHandle.parse(text) {
        case .none: player.venmoHandle = nil
        case .valid(let handle): player.venmoHandle = handle
        case .invalid: throw PaymentError.invalidVenmoHandle
        }
        try save()
    }

    private func removeMarkers(where matches: (PaidMarker) -> Bool) throws {
        let removed = round.paidMarkers.filter(matches)
        guard !removed.isEmpty else { return }
        round.paidMarkers.removeAll { marker in removed.contains { $0 === marker } }
        for marker in removed {
            marker.modelContext?.delete(marker)
        }
        try save()
    }

    private func save() throws {
        try round.modelContext?.save()
    }
}
