import Foundation

/// A payment the group marked paid, as a value. Money is integer cents.
struct PaidRecord: Hashable, Sendable {
    var payerID: String
    var payeeID: String
    var amountCents: Int
    var paidAt: Date

    /// The transfer it belongs to has the same payer, payee and amount.
    func matches(_ payment: RoundSettlement.Payment) -> Bool {
        payerID == payment.fromID && payeeID == payment.toID && amountCents == payment.amountCents
    }
}

extension RoundSettlement {
    /// Final, and nothing recorded is left unpaid by the engines. Only then is
    /// the settlement what is owed, and only then can a payment be made or
    /// marked paid (the backend's `final` status, docs/api.md).
    var isReadyForPayment: Bool {
        isFinal && unpaidGreenies.isEmpty
    }
}

/// The settlement's payments with what has been marked paid. The payments and
/// their amounts are the engine's; nothing is added up here.
///
/// The rules are the backend's (docs/api.md, Settlement): a paid marker
/// belongs to the transfer with its payer, payee and amount. When a score
/// correction changes the transfers, a marker that matches none of them is
/// stale: it is shown as recorded before the correction and never makes
/// another transfer paid.
struct PaymentStatus: Equatable, Sendable {
    struct Transfer: Equatable, Identifiable, Sendable {
        /// 1-based place among the settlement's payments.
        var number: Int
        var payment: RoundSettlement.Payment
        /// Nil when the transfer is not marked paid.
        var paidAt: Date?

        var id: Int { number }
        var isPaid: Bool { paidAt != nil }
    }

    struct StalePayment: Equatable, Identifiable, Sendable {
        var record: PaidRecord
        var payerName: String
        var payeeName: String

        var id: PaidRecord { record }
    }

    /// In the settlement's order.
    var transfers: [Transfer]
    /// Oldest first.
    var stalePayments: [StalePayment]
    /// Payments can be made and marked paid.
    var isReadyForPayment: Bool

    init(settlement: RoundSettlement, records: [PaidRecord]) {
        let records = records.sorted { $0.paidAt < $1.paidAt }
        transfers = settlement.payments.enumerated().map { offset, payment in
            // The first marker counts, like the backend keeps the first paidAt.
            Transfer(number: offset + 1, payment: payment, paidAt: records.first { $0.matches(payment) }?.paidAt)
        }
        stalePayments = records
            .filter { record in !settlement.payments.contains { record.matches($0) } }
            .map {
                StalePayment(record: $0, payerName: settlement.name($0.payerID), payeeName: settlement.name($0.payeeID))
            }
        isReadyForPayment = settlement.isReadyForPayment
    }

    var paidCount: Int {
        transfers.filter(\.isPaid).count
    }

    /// Every transfer of a final settlement is marked paid.
    var isAllSettled: Bool {
        isReadyForPayment && !transfers.isEmpty && transfers.allSatisfy(\.isPaid)
    }
}
