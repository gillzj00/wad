import SwiftData
import SwiftUI

/// Scores the round one hole at a time: gross scores, Wad makers in order and
/// the greenie winner, with the state of each game from the engines.
struct HoleScoringView: View {
    let round: Round

    @State private var holeNumber: Int
    @State private var failure: String?

    /// Opens on `startHole`, or on the first hole that is not complete. A
    /// round that started every hole at par has no such hole; it opens on hole 1.
    init(round: Round, startHole: Int? = nil) {
        self.round = round
        let resume = round.startsEveryHoleAtPar
            ? round.orderedHoles.first?.number
            : round.firstIncompleteHole ?? round.orderedHoles.last?.number
        _holeNumber = State(initialValue: startHole ?? resume ?? 1)
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
                Group {
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
                .themedRows()
            }
        }
        .listSectionSpacing(.compact)
        .themedList()
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
            HoleHeader(number: hole.number, par: hole.par, strokeIndex: hole.strokeIndex)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
        }
    }

    private func scores(_ hole: RoundHole, status: RoundStatus?) -> some View {
        Section {
            ForEach(round.orderedPlayers) { player in
                PlayerScoreRow(
                    name: player.displayName,
                    par: hole.par,
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
            SectionHeader("Scores", systemImage: "pencil.and.list.clipboard")
        } footer: {
            if status == nil {
                SectionFooter("Ticks and the games could not be computed.")
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
                .foregroundStyle(Theme.Palette.bone)
            }
            .accessibilityIdentifier("scoring.settlement")
            .emphasizedRows()
        } footer: {
            if let hole = round.firstIncompleteHole {
                SectionFooter("Hole \(hole) is not fully scored yet.")
            }
        }
    }

    @ViewBuilder
    private func skins(_ hole: RoundHole, status: RoundStatus?) -> some View {
        if let result = status?.skinsHole(hole.number) {
            Section {
                StatusLineView(line: ScoringText.skins(result, lastHole: lastHole, name: name))
                    .accessibilityIdentifier("status.skins")
            } header: {
                SectionHeader("Skins", systemImage: "dollarsign.circle")
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
            SectionHeader("Wad", systemImage: "banknote")
        } footer: {
            SectionFooter("Tap the players whose first putt qualified, in the order the putts were made. Tap again to remove.")
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
            SectionHeader("Greenie", systemImage: "flag.fill")
        } footer: {
            if candidates.isEmpty {
                SectionFooter("Nobody has par or better on this hole yet.")
            } else {
                SectionFooter("Only players with par or better are offered. The closest tee shot on the green wins.")
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
                    .frame(maxWidth: .infinity, minHeight: 24)
            }
            .buttonStyle(.secondary)
            .disabled(holeNumber <= 1)
            .accessibilityIdentifier("scoring.previous")

            Button {
                holeNumber += 1
            } label: {
                Label("Next hole", systemImage: "chevron.right")
                    .labelStyle(TrailingIconLabelStyle())
                    .frame(maxWidth: .infinity, minHeight: 24)
            }
            .buttonStyle(.primary)
            .disabled(holeNumber >= lastHole)
            .accessibilityIdentifier("scoring.next")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Theme.Palette.charcoal)
        .overlay(alignment: .top) { ChainDivider(color: Theme.Palette.rule, height: 8).offset(y: -4) }
    }
}

// MARK: - Pieces

/// The hole like on a tee marker: its number on a block, par and stroke index.
struct HoleHeader: View {
    let number: Int
    let par: Int
    let strokeIndex: Int

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.l) {
            HStack(alignment: .center, spacing: Theme.Spacing.m) {
                Text("\(number)")
                    .font(.system(.largeTitle, design: .rounded, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.crimson)
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.vertical, Theme.Spacing.xs)
                    .frame(minWidth: 64)
                    .background(
                        Theme.Palette.bone,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Image(systemName: "flag.fill")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.ember)
                    Text("Hole")
                        .font(Theme.Typography.overline)
                        .textCase(.uppercase)
                        .tracking(1)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Hole \(number)")
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("scoring.hole.title")

            Spacer(minLength: 0)

            HStack(spacing: Theme.Spacing.l) {
                fact("Par", value: par)
                fact("Stroke index", value: strokeIndex)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Par \(par) - Stroke index \(strokeIndex)")
            .accessibilityIdentifier("scoring.hole.detail")
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity)
        .foregroundStyle(Theme.Palette.bone)
        .background(
            Theme.Palette.maroon,
            in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        )
    }

    private func fact(_ title: String, value: Int) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title)
                .font(Theme.Typography.overline)
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(Theme.Palette.bone.opacity(0.85))
            Text("\(value)")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
        }
    }
}

/// Every hole as a chip: tap to jump. Completed holes are filled, the current
/// hole is outlined and a hole that needs fixing is red.
struct HoleStrip: View {
    let holes: [Int]
    @Binding var current: Int
    let completed: Set<Int>
    let flagged: Set<Int>

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var chipSize: CGFloat = 34

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(holes, id: \.self) { hole in
                        Button {
                            current = hole
                        } label: {
                            Text("\(hole)")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .monospacedDigit()
                                .frame(minWidth: chipSize, minHeight: chipSize)
                                .foregroundStyle(foreground(hole))
                                .background(background(hole), in: Circle())
                                .overlay {
                                    Circle().strokeBorder(
                                        Theme.Palette.rule,
                                        lineWidth: isFilled(hole) ? 0 : 1
                                    )
                                }
                                .padding(4)
                                .overlay {
                                    Circle().strokeBorder(Theme.Palette.bone, lineWidth: hole == current ? 2 : 0)
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
            .background(Theme.Palette.charcoal)
            .overlay(alignment: .bottom) { ChainDivider(color: Theme.Palette.rule, height: 8).offset(y: 4) }
            .onChange(of: current, initial: true) {
                if reduceMotion {
                    proxy.scrollTo(current, anchor: .center)
                } else {
                    withAnimation { proxy.scrollTo(current, anchor: .center) }
                }
            }
        }
    }

    private func isFilled(_ hole: Int) -> Bool {
        flagged.contains(hole) || completed.contains(hole)
    }

    private func foreground(_ hole: Int) -> Color {
        flagged.contains(hole) ? Theme.Palette.charcoal : Theme.Palette.bone
    }

    private func background(_ hole: Int) -> Color {
        if flagged.contains(hole) { return Theme.Palette.blood }
        if completed.contains(hole) { return Theme.Palette.crimson }
        return Theme.Palette.card
    }

    private func value(_ hole: Int) -> String {
        if flagged.contains(hole) { return "Needs fixing" }
        return completed.contains(hole) ? "Scored" : "Not scored"
    }
}

struct PlayerScoreRow: View {
    let name: String
    let par: Int
    let gross: Int?
    let ticks: Int?
    let net: Int?
    let onStep: (Int) -> Void
    let onClear: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var stepSize: CGFloat = 50
    @ScaledMetric(relativeTo: .title) private var markSize: CGFloat = 46

    private var detail: String {
        var parts: [String] = []
        if let ticks { parts.append(ScoringText.ticks(ticks)) }
        if let net { parts.append("Net \(net)") }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                player
                Spacer(minLength: 4)
                controls
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                player
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    controls
                }
            }
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 2)
    }

    private var player: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.headline)
                .lineLimit(1)
            Text(detail)
                .font(.caption)
                .foregroundStyle(Theme.Palette.ash)
                .monospacedDigit()
                .lineLimit(1)
                .accessibilityIdentifier("score.detail.\(name)")
            if let gross {
                // What the circles and squares around the score mean, in words.
                Text(ScoreNotation.name(gross: gross, par: par))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(gross < par ? Theme.Palette.blood : Theme.Palette.bone)
                    .lineLimit(1)
                    .accessibilityIdentifier("score.notation.\(name)")
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        if gross != nil {
            Button {
                onClear()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.Palette.ash)
                    .frame(minWidth: 32, minHeight: 44)
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
                .font(Theme.Typography.score)
                .monospacedDigit()
                .foregroundStyle(gross == nil ? Theme.Palette.ash : Theme.Palette.bone)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: gross)
                .frame(minWidth: markSize, minHeight: markSize)
                .background {
                    if let gross {
                        ScoreMark(notation: ScoreNotation(gross: gross, par: par), lineWidth: 2, gap: 2.5)
                    }
                }
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

    private func stepButton(systemImage: String, delta: Int) -> some View {
        Button {
            onStep(delta)
        } label: {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.Palette.blood)
                .frame(width: stepSize, height: stepSize)
                .background(Theme.Palette.blood.opacity(0.14), in: Circle())
                .overlay { Circle().strokeBorder(Theme.Palette.blood.opacity(0.35), lineWidth: 1) }
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
                        .frame(minWidth: 24, minHeight: 24)
                        .foregroundStyle(Theme.Palette.crimson)
                        .background(Theme.Palette.bone, in: Circle())
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
            .foregroundStyle(Theme.Palette.bone)
            .background(
                isSelected ? Theme.Palette.crimson : Theme.Palette.charcoal,
                in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .strokeBorder(Theme.Palette.rule, lineWidth: isSelected ? 0 : 1)
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct StatusLineView: View {
    let line: StatusLine
    /// On a row with the maroon background.
    var onMaroon = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if line.isWarning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Palette.blood)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(line.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(line.isWarning ? Theme.Palette.blood : Theme.Palette.bone)
                if let detail = line.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(onMaroon ? Theme.Palette.bone.opacity(0.85) : Theme.Palette.ash)
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
