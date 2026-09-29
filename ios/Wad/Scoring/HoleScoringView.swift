import SwiftData
import SwiftUI

/// Scores the round one hole at a time: gross scores, Wad makers in order and
/// the greenie winner, with the state of each game from the engines.
struct HoleScoringView: View {
    let round: Round

    @State private var holeNumber: Int
    @State private var failure: String?

    /// Opens on `startHole`, or on the first hole that is not complete.
    init(round: Round, startHole: Int? = nil) {
        self.round = round
        _holeNumber = State(
            initialValue: startHole ?? round.firstIncompleteHole ?? round.orderedHoles.last?.number ?? 1
        )
    }

    private var scorer: RoundScorer { RoundScorer(round: round) }
    private var lastHole: Int { round.orderedHoles.last?.number ?? RoundDraft.holeCount }

    private func name(_ playerID: String) -> String {
        round.players.first { $0.playerID == playerID }?.displayName ?? "Unknown player"
    }

    var body: some View {
        let status = SharedEngine.bridge.flatMap { try? RoundStatus(round: round, bridge: $0) }
        List {
            if let hole = round.hole(holeNumber) {
                header(hole)
                scores(hole, status: status)
                if hole.number == lastHole, round.isHoleComplete(hole.number) {
                    settlement
                }
                wad(hole, status: status)
                if hole.par == 3 || hole.greenieWinnerID != nil {
                    greenie(hole, status: status)
                }
                skins(hole, status: status)
            }
        }
        .listSectionSpacing(.compact)
        .navigationTitle(round.courseName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            HoleStrip(
                holes: round.orderedHoles.map(\.number),
                current: $holeNumber,
                completed: Set(round.completedHoles),
                flagged: Set(status?.invalidGreenieHoles ?? [])
            )
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { navigationBar }
        .alert("Could not save", isPresented: .constant(failure != nil)) {
            Button("OK") { failure = nil }
        } message: {
            Text(failure ?? "")
        }
    }

    private func perform(_ change: () throws -> Void) {
        do {
            try change()
        } catch {
            failure = String(describing: error)
        }
    }

    // MARK: Sections

    private func header(_ hole: RoundHole) -> some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                Text("Hole \(hole.number)")
                    .font(.title.bold())
                    .accessibilityIdentifier("scoring.hole.title")
                Spacer()
                Text("Par \(hole.par) - Stroke index \(hole.strokeIndex)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("scoring.hole.detail")
            }
        }
    }

    private func scores(_ hole: RoundHole, status: RoundStatus?) -> some View {
        Section {
            ForEach(round.orderedPlayers) { player in
                PlayerScoreRow(
                    name: player.displayName,
                    gross: round.gross(playerID: player.playerID, hole: hole.number),
                    ticks: status?.ticks(playerID: player.playerID, hole: hole.number),
                    net: status?.net(playerID: player.playerID, hole: hole.number),
                    onStep: { delta in
                        perform { try scorer.stepGross(by: delta, playerID: player.playerID, hole: hole.number) }
                    },
                    onClear: {
                        perform { try scorer.setGross(nil, playerID: player.playerID, hole: hole.number) }
                    }
                )
            }
            if !round.isHoleComplete(hole.number) {
                Button("Par for the rest", systemImage: "equal.circle") {
                    perform { try scorer.setParForUnscored(hole: hole.number) }
                }
                .accessibilityIdentifier("scoring.parForRest")
            }
        } header: {
            Text("Scores")
        } footer: {
            if status == nil {
                Text("Ticks and the games could not be computed.")
            }
        }
    }

    /// Offered on the last hole once it is scored.
    private var settlement: some View {
        Section {
            NavigationLink(value: RoundsRoute.settlement(round)) {
                Label(
                    round.firstIncompleteHole == nil ? "Settlement" : "Settlement (provisional)",
                    systemImage: "dollarsign.circle"
                )
                .font(.headline)
            }
            .accessibilityIdentifier("scoring.settlement")
        } footer: {
            if let hole = round.firstIncompleteHole {
                Text("Hole \(hole) is not fully scored yet.")
            }
        }
    }

    @ViewBuilder
    private func skins(_ hole: RoundHole, status: RoundStatus?) -> some View {
        if let result = status?.skinsHole(hole.number) {
            Section("Skins") {
                StatusLineView(line: ScoringText.skins(result, lastHole: lastHole, name: name))
                    .accessibilityIdentifier("status.skins")
            }
        }
    }

    private func wad(_ hole: RoundHole, status: RoundStatus?) -> some View {
        Section {
            ChoiceGrid {
                ForEach(round.orderedPlayers) { player in
                    let order = scorer.wadOrder(playerID: player.playerID, hole: hole.number)
                    ChoiceChip(
                        title: player.displayName,
                        badge: order.map(String.init),
                        isSelected: order != nil
                    ) {
                        perform { try scorer.toggleWadMaker(playerID: player.playerID, hole: hole.number) }
                    }
                    .accessibilityIdentifier("wad.maker.\(player.displayName)")
                    .accessibilityValue(order.map { "Make \($0)" } ?? "No make")
                }
            }
            if let instance = status?.wadInstance(hole: hole.number) {
                StatusLineView(line: ScoringText.wad(
                    instance,
                    makesOnHole: status?.wadMakes(hole: hole.number) ?? [],
                    name: name
                ))
                .accessibilityIdentifier("status.wad")
            }
        } header: {
            Text("Wad")
        } footer: {
            Text("Tap the players whose first putt qualified, in the order the putts were made. Tap again to remove.")
        }
    }

    private func greenie(_ hole: RoundHole, status: RoundStatus?) -> some View {
        let candidates = scorer.greenieCandidates(hole: hole.number)
        return Section {
            ChoiceGrid {
                ChoiceChip(title: "None", badge: nil, isSelected: hole.greenieWinnerID == nil) {
                    perform { try scorer.setGreenieWinner(nil, hole: hole.number) }
                }
                .accessibilityIdentifier("greenie.option.none")
                ForEach(candidates) { player in
                    ChoiceChip(
                        title: player.displayName,
                        badge: nil,
                        isSelected: hole.greenieWinnerID == player.playerID
                    ) {
                        perform { try scorer.setGreenieWinner(player.playerID, hole: hole.number) }
                    }
                    .accessibilityIdentifier("greenie.option.\(player.displayName)")
                }
            }
            if let result = status?.greenieHole(hole.number) {
                let line = ScoringText.greenie(result, amountCents: round.greeniesAmountCents, name: name)
                StatusLineView(line: line)
                    .accessibilityIdentifier("status.greenie")
                if line.isWarning {
                    Button("Clear the greenie", role: .destructive) {
                        perform { try scorer.setGreenieWinner(nil, hole: hole.number) }
                    }
                    .accessibilityIdentifier("greenie.clear")
                }
            }
        } header: {
            Text("Greenie")
        } footer: {
            if candidates.isEmpty {
                Text("Nobody has par or better on this hole yet.")
            } else {
                Text("Only players with par or better are offered. The closest tee shot on the green wins.")
            }
        }
    }

    // MARK: Navigation

    private var navigationBar: some View {
        HStack {
            Button {
                holeNumber -= 1
            } label: {
                Label("Previous", systemImage: "chevron.left")
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .disabled(holeNumber <= 1)
            .accessibilityIdentifier("scoring.previous")

            Button {
                holeNumber += 1
            } label: {
                Label("Next hole", systemImage: "chevron.right")
                    .labelStyle(TrailingIconLabelStyle())
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .disabled(holeNumber >= lastHole)
            .accessibilityIdentifier("scoring.next")
        }
        .buttonStyle(.bordered)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

// MARK: - Pieces

/// Every hole as a chip: tap to jump. Completed holes are filled, the current
/// hole is outlined and a hole that needs fixing is orange.
struct HoleStrip: View {
    let holes: [Int]
    @Binding var current: Int
    let completed: Set<Int>
    let flagged: Set<Int>

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(holes, id: \.self) { hole in
                        Button {
                            current = hole
                        } label: {
                            Text("\(hole)")
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .frame(width: 34, height: 34)
                                .foregroundStyle(foreground(hole))
                                .background(background(hole), in: Circle())
                                .padding(4)
                                .overlay {
                                    Circle().strokeBorder(Color.primary, lineWidth: hole == current ? 2 : 0)
                                }
                        }
                        .buttonStyle(.plain)
                        .id(hole)
                        .accessibilityLabel("Hole \(hole)")
                        .accessibilityValue(value(hole))
                        .accessibilityIdentifier("scoring.jump.\(hole)")
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
            .background(.bar)
            .onChange(of: current, initial: true) {
                withAnimation { proxy.scrollTo(current, anchor: .center) }
            }
        }
    }

    private func foreground(_ hole: Int) -> Color {
        flagged.contains(hole) || completed.contains(hole) ? .white : .primary
    }

    private func background(_ hole: Int) -> Color {
        if flagged.contains(hole) { return .orange }
        if completed.contains(hole) { return .accentColor }
        return Color(.tertiarySystemFill)
    }

    private func value(_ hole: Int) -> String {
        if flagged.contains(hole) { return "Needs fixing" }
        return completed.contains(hole) ? "Scored" : "Not scored"
    }
}

struct PlayerScoreRow: View {
    let name: String
    let gross: Int?
    let ticks: Int?
    let net: Int?
    let onStep: (Int) -> Void
    let onClear: () -> Void

    private var detail: String {
        var parts: [String] = []
        if let ticks { parts.append(ScoringText.ticks(ticks)) }
        if let net { parts.append("Net \(net)") }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .accessibilityIdentifier("score.detail.\(name)")
            }
            Spacer(minLength: 4)

            if gross != nil {
                Button {
                    onClear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Clear the score of \(name)")
                .accessibilityIdentifier("score.clear.\(name)")
            }

            stepButton(systemImage: "minus", delta: -1)
                .accessibilityLabel("One stroke fewer for \(name)")
                .accessibilityIdentifier("score.minus.\(name)")

            Button {
                onStep(0)
            } label: {
                Text(gross.map(String.init) ?? "-")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(gross == nil ? .secondary : .primary)
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Score of \(name)")
            .accessibilityValue(gross.map(String.init) ?? "Not set")
            .accessibilityIdentifier("score.value.\(name)")

            stepButton(systemImage: "plus", delta: 1)
                .accessibilityLabel("One stroke more for \(name)")
                .accessibilityIdentifier("score.plus.\(name)")
        }
        .buttonStyle(.borderless)
    }

    private func stepButton(systemImage: String, delta: Int) -> some View {
        Button {
            onStep(delta)
        } label: {
            Image(systemName: systemImage)
                .font(.headline)
                .frame(width: 44, height: 44)
                .background(Color(.tertiarySystemFill), in: Circle())
        }
    }
}

/// Two columns of chips.
struct ChoiceGrid<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
            content
        }
        .buttonStyle(.borderless)
        .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
    }
}

struct ChoiceChip: View {
    let title: String
    /// Shown in front of the title, e.g. the order of a Wad make.
    let badge: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let badge {
                    Text(badge)
                        .font(.subheadline.bold())
                        .monospacedDigit()
                        .frame(width: 24, height: 24)
                        .foregroundStyle(Color.accentColor)
                        .background(.white, in: Circle())
                } else if isSelected {
                    Image(systemName: "checkmark")
                        .font(.subheadline.bold())
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(
                isSelected ? Color.accentColor : Color(.tertiarySystemFill),
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct StatusLineView: View {
    let line: StatusLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if line.isWarning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(line.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(line.isWarning ? .orange : .primary)
                if let detail = line.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon
        }
    }
}

#if DEBUG
#Preview {
    let container = try! ModelContainer(for: Round.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let round = try! RoundDraft.sample.makeRound(using: SharedEngine.bridge!)
    container.mainContext.insert(round)
    return NavigationStack { HoleScoringView(round: round) }
        .modelContainer(container)
}
#endif
