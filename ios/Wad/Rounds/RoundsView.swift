import SwiftData
import SwiftUI

/// Screens pushed on the Rounds tab.
enum RoundsRoute: Hashable {
    case detail(Round)
    case scoring(Round)
    /// Scoring, opened on a hole.
    case scoringHole(Round, Int)
    case settlement(Round)
}

/// The Rounds tab: the history of the rounds, newest first, and the way into a
/// new round.
struct RoundsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Round.startedAt, order: .reverse) private var rounds: [Round]

    @State private var path: [RoundsRoute] = []
    @State private var setup: SetupPresentation?
    @State private var summaries = RoundSummaryCache()
    @State private var roundToDelete: Round?
    #if DEBUG
    @State private var appliedDebugLaunchArguments = false
    #endif

    struct SetupPresentation: Identifiable {
        let id = UUID()
        var draft = RoundDraft()
        var step = SetupStep.course
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if rounds.isEmpty {
                    EmptyStateView(
                        title: "No rounds yet",
                        message: "Set up a course, the players and the games to start one."
                    ) {
                        Button("New round") { setup = SetupPresentation() }
                            .buttonStyle(.primary)
                    }
                } else {
                    List {
                        // A section per round, so that each round is a card.
                        ForEach(rounds) { round in
                            Section {
                                NavigationLink(value: RoundsRoute.detail(round)) {
                                    RoundHistoryRow(round: round, summaries: summaries)
                                }
                                .accessibilityIdentifier("rounds.row.\(round.courseName)")
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button("Delete", systemImage: "trash") { roundToDelete = round }
                                        .tint(Theme.Palette.flagRed)
                                }
                            }
                        }
                        .themedRows()
                    }
                    .listSectionSpacing(Theme.Spacing.m)
                    .themedList()
                }
            }
            .navigationTitle("Rounds")
            .navigationDestination(for: RoundsRoute.self) { route in
                switch route {
                case .detail(let round): RoundDetailView(round: round)
                case .scoring(let round): HoleScoringView(round: round)
                case .scoringHole(let round, let hole): HoleScoringView(round: round, startHole: hole)
                case .settlement(let round): SettlementView(round: round)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New round", systemImage: "plus") { setup = SetupPresentation() }
                }
            }
            .alert(
                "Delete this round?",
                isPresented: Binding { roundToDelete != nil } set: { if !$0 { roundToDelete = nil } },
                presenting: roundToDelete
            ) { round in
                Button("Delete round", role: .destructive) { delete(round) }
                Button("Cancel", role: .cancel) {}
            } message: { round in
                Text("\(round.courseName), \(RoundHistoryRow.date(round.startedAt)). "
                    + "Its scores and the payments marked paid are deleted with it.")
            }
            .sheet(item: $setup) { setup in
                RoundSetupView(draft: setup.draft, step: setup.step) { round in
                    path = [.detail(round)]
                }
            }
            #if DEBUG
            .safeAreaInset(edge: .bottom) {
                if ProcessInfo.processInfo.arguments.contains(LaunchArgument.debugStoreCounts) {
                    StoreCountsView()
                }
            }
            .task { applyDebugLaunchArguments() }
            #endif
        }
    }

    private func delete(_ round: Round) {
        summaries.remove(round.id)
        modelContext.delete(round)
        try? modelContext.save()
    }

    #if DEBUG
    /// `-debugSetupStep course|players|games` opens the setup flow at that step
    /// with the sample draft; `-debugSetupStep detail` creates the sample round
    /// and opens it. `-debugSeedRound finalPush` creates a finished round with an
    /// unresolved skins carryover and opens it; `-debugSeedStartedAt <seconds
    /// since 1970>` gives it that start. `-debugSeedRound gallery` creates
    /// several rounds and stays on the list. For simulator screenshots and the UI tests.
    private func applyDebugLaunchArguments() {
        // The task runs again when the list comes back on screen.
        guard !appliedDebugLaunchArguments else { return }
        appliedDebugLaunchArguments = true
        let seed = UserDefaults.standard.string(forKey: "debugSeedRound")
        let seconds = UserDefaults.standard.string(forKey: "debugSeedStartedAt")
        let startedAt = seconds.flatMap(Int.init).map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? .now
        if seed == "gallery" {
            guard
                let bridge = SharedEngine.bridge,
                let rounds = try? DebugRounds.gallery(using: bridge, startedAt: startedAt)
            else { return }
            rounds.forEach(modelContext.insert)
            try? modelContext.save()
            return
        }
        if seed == "finalPush" {
            guard
                let bridge = SharedEngine.bridge,
                let round = try? DebugRounds.finalPush(using: bridge, startedAt: startedAt)
            else { return }
            modelContext.insert(round)
            try? modelContext.save()
            path = [.detail(round)]
            return
        }
        guard let value = UserDefaults.standard.string(forKey: "debugSetupStep") else { return }
        switch value {
        case "course": setup = SetupPresentation(draft: .sample, step: .course)
        case "players": setup = SetupPresentation(draft: .sample, step: .players)
        case "games": setup = SetupPresentation(draft: .sample, step: .games)
        case "detail":
            guard let bridge = SharedEngine.bridge, let round = try? RoundDraft.sample.makeRound(using: bridge) else { return }
            modelContext.insert(round)
            try? modelContext.save()
            path = [.detail(round)]
        default: break
        }
    }
    #endif
}

/// A round in the history: course, date, players, how far the round is and,
/// once it is final, the result and whether it is settled. The result comes
/// from the engines through `RoundSummaryCache`, outside of the rendering.
struct RoundHistoryRow: View {
    let round: Round
    let summaries: RoundSummaryCache

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
    }

    var body: some View {
        let key = RoundSummaryKey(round: round)
        let summary = summaries.summary(for: round, key: key) ?? summaries.lastSummary(for: round)
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            badge(summary)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(round.courseName)
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(Theme.Palette.ink)
                Text(Self.date(round.startedAt))
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.ink)
                Text(round.orderedPlayers.map(\.displayName).joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.inkSecondary)
                if let summary {
                    Text(summary.progressText)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(summary.progress == .final ? Theme.Palette.gold : Theme.Palette.fairway)
                        .padding(.top, 2)
                    if let settled = summary.settledText {
                        StatPill(
                            text: settled,
                            systemImage: summary.settled == .allSettled ? "checkmark.seal.fill" : "circle.dashed",
                            tone: tone(summary.settled)
                        )
                        .padding(.top, 2)
                    }
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .task(id: key) {
            // After the row is on screen, so that scrolling does not wait for the engines.
            await Task.yield()
            summaries.refresh(round, key: key, bridge: SharedEngine.bridge)
        }
    }

    /// A flag while the round is played, a checkered one when it is final.
    private func badge(_ summary: RoundSummary?) -> some View {
        let isFinal = summary?.progress == .final
        return Image(systemName: isFinal ? "flag.checkered" : "flag.fill")
            .font(.headline)
            .foregroundStyle(isFinal ? Theme.Palette.onGreen : Theme.Palette.fairway)
            .padding(10)
            .background(
                isFinal ? Theme.Palette.deepGreen : Theme.Palette.fairway.opacity(0.14),
                in: Circle()
            )
            .accessibilityHidden(true)
    }

    private func tone(_ settled: RoundSummary.Settled?) -> StatPill.Tone {
        switch settled {
        case .allSettled, .nothingOwed: .brand
        case .needsFixing, .unsettled: .warning
        case nil: .neutral
        }
    }
}

#if DEBUG
/// What the store holds, for the UI tests (`-debugStoreCounts`).
private struct StoreCountsView: View {
    @Query private var rounds: [Round]
    @Query private var holes: [RoundHole]
    @Query private var players: [RoundPlayer]
    @Query private var scores: [HoleScore]

    var body: some View {
        Text("Stored: \(rounds.count) rounds, \(holes.count) holes, \(players.count) players, \(scores.count) scores")
            .font(.caption)
            .foregroundStyle(Theme.Palette.inkSecondary)
            .padding(.bottom, 4)
            .accessibilityIdentifier("debug.storeCounts")
    }
}
#endif
