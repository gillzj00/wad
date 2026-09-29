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
                    ContentUnavailableView {
                        Label("No rounds yet", systemImage: "flag")
                    } description: {
                        Text("Set up a course, the players and the games to start one.")
                    } actions: {
                        Button("New round") { setup = SetupPresentation() }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(rounds) { round in
                            NavigationLink(value: RoundsRoute.detail(round)) {
                                RoundHistoryRow(round: round, summaries: summaries)
                            }
                            .accessibilityIdentifier("rounds.row.\(round.courseName)")
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", systemImage: "trash") { roundToDelete = round }
                                    .tint(.red)
                            }
                        }
                    }
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
    /// since 1970>` gives it that start. For simulator screenshots and the UI tests.
    private func applyDebugLaunchArguments() {
        // The task runs again when the list comes back on screen.
        guard !appliedDebugLaunchArguments else { return }
        appliedDebugLaunchArguments = true
        if UserDefaults.standard.string(forKey: "debugSeedRound") == "finalPush" {
            let seconds = UserDefaults.standard.string(forKey: "debugSeedStartedAt")
            let startedAt = seconds.flatMap(Int.init).map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? .now
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
        VStack(alignment: .leading, spacing: 3) {
            Text(round.courseName).font(.headline)
            Text(Self.date(round.startedAt))
                .font(.subheadline)
            Text(round.orderedPlayers.map(\.displayName).joined(separator: ", "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let summary {
                Text(summary.progressText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                if let settled = summary.settledText {
                    Label(settled, systemImage: summary.settled == .allSettled ? "checkmark.seal.fill" : "circle.dashed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color(summary.settled))
                }
            }
        }
        .task(id: key) {
            // After the row is on screen, so that scrolling does not wait for the engines.
            await Task.yield()
            summaries.refresh(round, key: key, bridge: SharedEngine.bridge)
        }
    }

    private func color(_ settled: RoundSummary.Settled?) -> Color {
        switch settled {
        case .allSettled, .nothingOwed: .green
        case .needsFixing, .unsettled: .orange
        case nil: .secondary
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
            .foregroundStyle(.secondary)
            .padding(.bottom, 4)
            .accessibilityIdentifier("debug.storeCounts")
    }
}
#endif
