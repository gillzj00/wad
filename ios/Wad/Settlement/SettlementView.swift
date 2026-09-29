import SwiftData
import SwiftUI

/// The round's settlement: who pays whom, each player's position in total and
/// per game, and the detail of each game. Everything comes from the engines
/// through `RoundSettlement`.
struct SettlementView: View {
    let round: Round

    var body: some View {
        let settlement = SharedEngine.bridge.flatMap { try? RoundSettlement(round: round, bridge: $0) }
        List {
            if let settlement {
                status(settlement)
                payments(settlement)
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

    private func payments(_ settlement: RoundSettlement) -> some View {
        Section {
            if settlement.payments.isEmpty {
                Text(SettlementText.noPayments(settlement))
                    .font(.title3.weight(.semibold))
                    .accessibilityIdentifier("settlement.noPayments")
            }
            ForEach(Array(settlement.payments.enumerated()), id: \.offset) { offset, payment in
                HStack(alignment: .firstTextBaseline) {
                    Text("\(payment.fromName) pays \(payment.toName)")
                        .font(.title3.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(ScoringText.dollars(payment.amountCents))
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(SettlementText.payment(payment))
                .accessibilityIdentifier("settlement.payment.\(offset + 1)")
            }
        } header: {
            Text(SettlementText.paymentsHeader(settlement))
        } footer: {
            if !settlement.isFinal {
                Text("Provisional: nothing is owed until the round is finished.")
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
