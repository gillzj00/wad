import Foundation

/// Wording of the payments. Amounts are integer cents formatted by `Money`.
enum PaymentText {
    static func paidOn(_ date: Date) -> String {
        "Paid " + date.formatted(date: .abbreviated, time: .shortened)
    }

    static func state(_ transfer: PaymentStatus.Transfer) -> String {
        transfer.paidAt.map(paidOn) ?? "Not paid"
    }

    /// Who does what in Venmo, with the handle the link goes to. Nil without the handle.
    static func venmoDetail(_ kind: VenmoLink.Kind, payment: RoundSettlement.Payment, recipient: String?) -> String? {
        guard let recipient else { return nil }
        let amount = ScoringText.dollars(payment.amountCents)
        let handle = VenmoHandle.display(recipient)
        switch kind {
        case .pay:
            return "\(payment.fromName) pays \(payment.toName) (\(handle)) \(amount). On \(payment.fromName)'s phone."
        case .request:
            return "\(payment.toName) requests \(amount) from \(payment.fromName) (\(handle)). On \(payment.toName)'s phone."
        }
    }

    /// The player whose handle the link needs.
    static func recipientName(_ kind: VenmoLink.Kind, payment: RoundSettlement.Payment) -> String {
        kind == .pay ? payment.toName : payment.fromName
    }

    static func recipientID(_ kind: VenmoLink.Kind, payment: RoundSettlement.Payment) -> String {
        kind == .pay ? payment.toID : payment.fromID
    }

    static func missingHandle(_ kind: VenmoLink.Kind, payment: RoundSettlement.Payment) -> String {
        "\(recipientName(kind, payment: payment)) has no Venmo handle."
    }

    static func stale(_ stale: PaymentStatus.StalePayment) -> StatusLine {
        StatusLine(
            title: "\(stale.payerName) paid \(stale.payeeName) \(ScoringText.dollars(stale.record.amountCents))",
            detail: "Recorded before a correction, on "
                + stale.record.paidAt.formatted(date: .abbreviated, time: .shortened)
                + ". It matches no payment of the settlement as it is now, so it marks none of them paid.",
            isWarning: true
        )
    }
}
