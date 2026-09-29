import SwiftData
import SwiftUI

/// One payment of the settlement: pay or request it with Venmo, and mark it
/// paid or not paid. One phone scores for the group, so the app cannot know
/// whether the payer or the payee holds it and offers both.
///
/// The app never moves money and never assumes that a payment was made:
/// after Venmo was opened it asks before it marks anything paid.
struct PaymentSheet: View {
    @Environment(\.dismiss) private var dismiss

    let round: Round
    let settlement: RoundSettlement
    let transfer: PaymentStatus.Transfer
    var opener = LinkOpener.shared

    @State private var confirmsPaid = false
    @State private var failedKind: VenmoLink.Kind?
    @State private var handleEdit: VenmoHandleEdit?
    @State private var failure: String?

    private var payment: RoundSettlement.Payment { transfer.payment }
    private var ledger: PaymentLedger { PaymentLedger(round: round) }
    private var canPay: Bool { settlement.isReadyForPayment && !transfer.isPaid }

    private var summary: String { SettlementText.payment(payment) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(payment.fromName) pays \(payment.toName)")
                            .font(.title3.weight(.semibold))
                        Text(ScoringText.dollars(payment.amountCents))
                            .font(.largeTitle.bold())
                            .monospacedDigit()
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(summary)
                    .accessibilityIdentifier("payment.summary")

                    Label(PaymentText.state(transfer), systemImage: transfer.isPaid ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(transfer.isPaid ? .green : .secondary)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(PaymentText.state(transfer))
                        .accessibilityIdentifier("payment.state")
                }

                if canPay {
                    venmo
                }
                marking

                #if DEBUG
                if opener.stub != nil {
                    Section("Debug: links opened") {
                        Text(opener.recorded.last?.absoluteString ?? "None")
                            .font(.caption.monospaced())
                            .accessibilityIdentifier("debug.openedLink")
                    }
                }
                #endif
            }
            .navigationTitle("Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("payment.done")
                }
            }
            .alert("Was the payment made?", isPresented: $confirmsPaid) {
                Button("Mark as paid") { markPaid() }
                Button("Not yet", role: .cancel) {}
            } message: {
                Text("Wad cannot see what happened in Venmo. Mark \"\(summary)\" as paid only if the payment went through.")
            }
            .alert(
                "Venmo could not be opened",
                isPresented: Binding { failedKind != nil } set: { if !$0 { failedKind = nil } },
                presenting: failedKind
            ) { kind in
                Button("Open venmo.com") { openVenmo(kind, web: true) }
                Button("Mark as paid by hand") { markPaid() }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("The Venmo app may not be installed on this phone. "
                    + "You can use the Venmo website, or pay another way and mark the payment as paid.")
            }
            .alert("Could not save", isPresented: Binding { failure != nil } set: { if !$0 { failure = nil } }) {
                Button("OK") {}
            } message: {
                Text(failure ?? "")
            }
            .sheet(item: $handleEdit) { edit in
                VenmoHandleEditor(round: round, edit: edit)
            }
        }
    }

    // MARK: Sections

    private var venmo: some View {
        Section {
            venmoAction(.pay, title: "Pay with Venmo", systemImage: "arrow.up.right.circle")
            venmoAction(.request, title: "Request with Venmo", systemImage: "arrow.down.left.circle")
        } header: {
            Text("Venmo")
        } footer: {
            Text("Venmo opens with the amount filled in, and the payment is made there. Wad never moves money.")
        }
    }

    @ViewBuilder
    private func venmoAction(_ kind: VenmoLink.Kind, title: String, systemImage: String) -> some View {
        let recipient = handle(of: PaymentText.recipientID(kind, payment: payment))
        let detail = PaymentText.venmoDetail(kind, payment: payment, recipient: recipient)
            ?? PaymentText.missingHandle(kind, payment: payment)
        Button {
            openVenmo(kind, web: false)
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: systemImage)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(recipient == nil)
        .accessibilityLabel(title)
        .accessibilityValue(detail)
        .accessibilityIdentifier("payment.venmo.\(kind.rawValue)")

        if recipient == nil {
            let name = PaymentText.recipientName(kind, payment: payment)
            Button("Add \(name)'s Venmo handle", systemImage: "at") {
                handleEdit = VenmoHandleEdit(playerID: PaymentText.recipientID(kind, payment: payment), name: name)
            }
            .accessibilityIdentifier("payment.addHandle.\(name)")
        }
    }

    private var marking: some View {
        Section {
            if transfer.isPaid {
                Button("Mark as not paid", systemImage: "arrow.uturn.backward.circle", role: .destructive) {
                    perform { try ledger.markUnpaid(payment) }
                }
                .accessibilityIdentifier("payment.markUnpaid")
            } else if settlement.isReadyForPayment {
                Button("Mark as paid", systemImage: "checkmark.circle") {
                    markPaid()
                }
                .accessibilityIdentifier("payment.markPaid")
            }
        } footer: {
            if !transfer.isPaid, settlement.isReadyForPayment {
                Text("For a payment made in cash or any other way.")
            }
        }
    }

    // MARK: Actions

    private func handle(of playerID: String) -> String? {
        round.players.first { $0.playerID == playerID }?.venmoHandle
    }

    private func link(_ kind: VenmoLink.Kind, web: Bool) -> URL? {
        guard let recipient = handle(of: PaymentText.recipientID(kind, payment: payment)) else { return nil }
        let note = VenmoLink.note(courseName: round.courseName, date: round.startedAt)
        return web
            ? VenmoLink.webURL(kind: kind, recipient: recipient, amountCents: payment.amountCents, note: note)
            : VenmoLink.appURL(kind: kind, recipient: recipient, amountCents: payment.amountCents, note: note)
    }

    private func openVenmo(_ kind: VenmoLink.Kind, web: Bool) {
        guard canPay, let url = link(kind, web: web) else { return }
        Task {
            if await opener.open(url) {
                confirmsPaid = true
            } else if web {
                failure = "The Venmo website could not be opened."
            } else {
                failedKind = kind
            }
        }
    }

    private func markPaid() {
        perform { try ledger.markPaid(payment, in: settlement) }
    }

    private func perform(_ change: () throws -> Void) {
        do {
            try change()
        } catch {
            failure = String(describing: error)
        }
    }
}
