import SwiftData
import SwiftUI

/// The round's settlement: who pays whom, each player's position in total and
/// per game, and the detail of each game. Everything comes from the engines
/// through `RoundSettlement`.
struct SettlementView: View {
    let round: Round

    @State private var selected: SelectedPayment?
    @State private var failure: String?

    var body: some View {
        let settlement = SharedEngine.bridge.flatMap { try? RoundSettlement(round: round, bridge: $0) }
        List {
            if let settlement {
                let paymentStatus = PaymentStatus(settlement: settlement, records: round.paidRecords)
                status(settlement)
                payments(settlement, status: paymentStatus)
                stalePayments(paymentStatus)
                positions(settlement)
                games(settlement)
                skins(settlement)
                wad(settlement)
                greenies(settlement)
            } else {
                Section {
                    StatusLineView(line: StatusLine(
                        title: "The settlement could not be computed",
                        detail: "Check the scores of the round.",
                        isWarning: true
                    ))
                    .accessibilityIdentifier("settlement.failed")
                }
            }
        }
        .navigationTitle("Settlement")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $selected) { selected in
            SelectedPaymentView(round: round, selected: selected)
        }
        .alert("Could not save", isPresented: Binding { failure != nil } set: { if !$0 { failure = nil } }) {
            Button("OK") {}
        } message: {
            Text(failure ?? "")
        }
    }

    // MARK: Sections

    @ViewBuilder
    private func status(_ settlement: RoundSettlement) -> some View {
        Section {
            StatusLineView(line: SettlementText.status(settlement))
                .accessibilityIdentifier("settlement.status")
        }

        if let carryover = settlement.unresolvedSkinsCarryoverCents {
            let line = SettlementText.unresolvedCarryover(cents: carryover, lastHole: settlement.lastHole)
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Label {
                        Text(line.title)
                            .font(.headline)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .foregroundStyle(.orange)
                    Text(line.detail ?? "")
                        .font(.subheadline)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel([line.title, line.detail].compactMap { $0 }.joined(separator: ". "))
                .accessibilityIdentifier("settlement.carryover")
            }
        }

        if !settlement.unpaidGreenies.isEmpty {
            Section("Needs fixing") {
                ForEach(settlement.unpaidGreenies, id: \.hole) { greenie in
                    NavigationLink(value: RoundsRoute.scoringHole(round, greenie.hole)) {
                        StatusLineView(line: SettlementText.unpaidGreenie(greenie, name: settlement.name))
                    }
                    .accessibilityIdentifier("settlement.fix.greenie.\(greenie.hole)")
                }
            }
        }
    }

    private func payments(_ settlement: RoundSettlement, status: PaymentStatus) -> some View {
        Section {
            if status.isAllSettled {
                Label("All settled", systemImage: "checkmark.seal.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("settlement.allSettled")
            }
            if settlement.payments.isEmpty {
                Text(SettlementText.noPayments(settlement))
                    .font(.title3.weight(.semibold))
                    .accessibilityIdentifier("settlement.noPayments")
            }
            ForEach(status.transfers) { transfer in
                // Payments are made and marked paid on a final settlement only.
                // One that is marked paid can always be marked not paid.
                if status.isReadyForPayment || transfer.isPaid {
                    Button {
                        selected = SelectedPayment(payment: transfer.payment)
                    } label: {
                        PaymentRow(transfer: transfer, showsState: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(SettlementText.payment(transfer.payment))
                    .accessibilityValue(transfer.isPaid ? "Paid" : "Not paid")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("settlement.payment.\(transfer.number)")
                } else {
                    PaymentRow(transfer: transfer, showsState: false)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(SettlementText.payment(transfer.payment))
                        .accessibilityIdentifier("settlement.payment.\(transfer.number)")
                }
            }
        } header: {
            Text(SettlementText.paymentsHeader(settlement))
        } footer: {
            if !settlement.isFinal {
                Text("Provisional: nothing is owed until the round is finished.")
            } else if !status.isReadyForPayment {
                Text("Payments can be made once what needs fixing is fixed.")
            } else if !settlement.payments.isEmpty {
                Text("Tap a payment to pay or request it with Venmo, or to mark it paid. Wad never moves money.")
            }
        }
    }

    @ViewBuilder
    private func stalePayments(_ status: PaymentStatus) -> some View {
        if !status.stalePayments.isEmpty {
            Section {
                ForEach(Array(status.stalePayments.enumerated()), id: \.element.id) { offset, stale in
                    StatusLineView(line: PaymentText.stale(stale))
                        .accessibilityIdentifier("settlement.stale.\(offset + 1)")
                    // A row of its own, full width, so that it can be tapped on every iOS version.
                    Button("Remove this payment", systemImage: "trash", role: .destructive) {
                        do {
                            try PaymentLedger(round: round).removeStale(stale.record)
                        } catch {
                            failure = String(describing: error)
                        }
                    }
                    .accessibilityIdentifier("settlement.stale.\(offset + 1).remove")
                }
            } header: {
                Text("Recorded before a correction")
            } footer: {
                Text("The scores changed after these payments were marked paid. Settle the difference, then remove them.")
            }
        }
    }

    private func positions(_ settlement: RoundSettlement) -> some View {
        Section(settlement.isFinal ? "Net position" : "Net position (provisional)") {
            ForEach(settlement.players) { player in
                HStack {
                    Text(player.name)
                    Spacer(minLength: 8)
                    Text(SettlementText.position(player.netCents))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(color(player.netCents))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(player.name): \(SettlementText.position(player.netCents))")
                .accessibilityIdentifier("settlement.position.\(player.name)")
            }
        }
    }

    private func games(_ settlement: RoundSettlement) -> some View {
        Section(settlement.isFinal ? "By game" : "By game (provisional)") {
            HStack(spacing: 0) {
                Text("").frame(maxWidth: .infinity, alignment: .leading)
                amountCell("Skins")
                amountCell("Wad")
                amountCell("Greenies")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)

            ForEach(settlement.players) { player in
                HStack(spacing: 0) {
                    Text(player.name)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    amountCell(SettlementText.signed(player.skinsCents)).foregroundStyle(color(player.skinsCents))
                    amountCell(SettlementText.signed(player.wadCents)).foregroundStyle(color(player.wadCents))
                    amountCell(SettlementText.signed(player.greeniesCents)).foregroundStyle(color(player.greeniesCents))
                }
                .font(.subheadline)
                .monospacedDigit()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(SettlementText.games(player))
                .accessibilityIdentifier("settlement.games.\(player.name)")
            }
        }
    }

    private func skins(_ settlement: RoundSettlement) -> some View {
        Section {
            ForEach(settlement.skins.holes, id: \.hole) { hole in
                HoleLineRow(
                    hole: hole.hole,
                    line: ScoringText.skins(hole, lastHole: settlement.lastHole, name: settlement.name)
                )
                .accessibilityIdentifier("settlement.skins.\(hole.hole)")
            }
        } header: {
            Text("Skins")
        } footer: {
            if let carryover = settlement.unresolvedSkinsCarryoverCents {
                Text("\(ScoringText.dollars(carryover)) is unresolved after hole \(settlement.lastHole) and is not paid out.")
            }
        }
    }

    private func wad(_ settlement: RoundSettlement) -> some View {
        ForEach(settlement.wadInstances, id: \.segment) { instance in
            Section(instance.segment == .front ? "Wad, front nine" : "Wad, back nine") {
                StatusLineView(line: ScoringText.wad(instance, makesOnHole: [], name: settlement.name))
                    .accessibilityIdentifier("settlement.wad.\(instance.segment.rawValue)")
                ForEach(Array(instance.makes.enumerated()), id: \.offset) { offset, make in
                    Text(SettlementText.wadMake(make, name: settlement.name))
                        .font(.subheadline)
                        .monospacedDigit()
                        .accessibilityIdentifier("settlement.wad.\(instance.segment.rawValue).make.\(offset + 1)")
                }
            }
        }
    }

    private func greenies(_ settlement: RoundSettlement) -> some View {
        Section("Greenies") {
            if settlement.greenieHoles.isEmpty {
                Text("The course has no par 3.")
                    .foregroundStyle(.secondary)
            }
            ForEach(settlement.greenieHoles, id: \.hole) { hole in
                HoleLineRow(
                    hole: hole.hole,
                    line: ScoringText.greenie(hole, amountCents: settlement.greeniesAmountCents, name: settlement.name)
                )
                .accessibilityIdentifier("settlement.greenie.\(hole.hole)")
            }
        }
    }

    // MARK: Pieces

    private func amountCell(_ text: String) -> some View {
        Text(text)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: 80, alignment: .trailing)
    }

    private func color(_ cents: Int) -> Color {
        if cents > 0 { return .green }
        return cents < 0 ? .red : .secondary
    }
}

/// The payment a sheet is open for: its payer, payee and amount.
struct SelectedPayment: Identifiable, Hashable {
    var payerID: String
    var payeeID: String
    var amountCents: Int

    init(payment: RoundSettlement.Payment) {
        payerID = payment.fromID
        payeeID = payment.toID
        amountCents = payment.amountCents
    }

    var id: Self { self }

    func matches(_ payment: RoundSettlement.Payment) -> Bool {
        payerID == payment.fromID && payeeID == payment.toID && amountCents == payment.amountCents
    }
}

/// The payment sheet for the selected payment, as the settlement has it now.
private struct SelectedPaymentView: View {
    @Environment(\.dismiss) private var dismiss

    let round: Round
    let selected: SelectedPayment

    var body: some View {
        let settlement = SharedEngine.bridge.flatMap { try? RoundSettlement(round: round, bridge: $0) }
        let transfer = settlement.flatMap { settlement in
            PaymentStatus(settlement: settlement, records: round.paidRecords)
                .transfers.first { selected.matches($0.payment) }
        }
        if let settlement, let transfer {
            PaymentSheet(round: round, settlement: settlement, transfer: transfer)
        } else {
            ContentUnavailableView {
                Label("The settlement has changed", systemImage: "arrow.triangle.2.circlepath")
            } description: {
                Text("This payment is no longer part of it.")
            } actions: {
                Button("Close") { dismiss() }
            }
        }
    }
}

/// A payment of the settlement and, on a final settlement, whether it is paid.
private struct PaymentRow: View {
    let transfer: PaymentStatus.Transfer
    let showsState: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(transfer.payment.fromName) pays \(transfer.payment.toName)")
                    .font(.title3.weight(.semibold))
                Spacer(minLength: 8)
                Text(ScoringText.dollars(transfer.payment.amountCents))
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
            }
            if showsState {
                HStack {
                    Label(
                        PaymentText.state(transfer),
                        systemImage: transfer.isPaid ? "checkmark.circle.fill" : "circle"
                    )
                    .foregroundStyle(transfer.isPaid ? .green : .secondary)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .font(.subheadline)
            }
        }
        .contentShape(Rectangle())
    }
}

/// A game's result on a hole, with the hole number in front.
struct HoleLineRow: View {
    let hole: Int
    let line: StatusLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(hole)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
            StatusLineView(line: line)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hole \(hole): " + [line.title, line.detail].compactMap { $0 }.joined(separator: ". "))
    }
}

#if DEBUG
#Preview {
    let container = try! ModelContainer(for: Round.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let round = try! DebugRounds.finalPush(using: SharedEngine.bridge!)
    container.mainContext.insert(round)
    return NavigationStack { SettlementView(round: round) }
        .modelContainer(container)
}
#endif
