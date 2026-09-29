import SwiftData
import SwiftUI

/// The Rounds tab: saved rounds, newest first, and the way into a new round.
struct RoundsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Round.startedAt, order: .reverse) private var rounds: [Round]

    @State private var path: [Round] = []
    @State private var setup: SetupPresentation?

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
                            NavigationLink(value: round) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(round.courseName).font(.headline)
                                    Text(round.orderedPlayers.map(\.displayName).joined(separator: ", "))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text(round.startedAt, format: .dateTime.month().day().year().hour().minute())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Rounds")
            .navigationDestination(for: Round.self) { RoundDetailView(round: $0) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New round", systemImage: "plus") { setup = SetupPresentation() }
                }
            }
            .sheet(item: $setup) { setup in
                RoundSetupView(draft: setup.draft, step: setup.step) { round in
                    path = [round]
                }
            }
            #if DEBUG
            .task { applyDebugLaunchArguments() }
            #endif
        }
    }

    private func delete(at offsets: IndexSet) {
        for offset in offsets {
            modelContext.delete(rounds[offset])
        }
        try? modelContext.save()
    }

    #if DEBUG
    /// `-debugSetupStep course|players|games` opens the setup flow at that step
    /// with the sample draft; `-debugSetupStep detail` creates the sample round
    /// and opens it. For simulator screenshots.
    private func applyDebugLaunchArguments() {
        guard let value = UserDefaults.standard.string(forKey: "debugSetupStep") else { return }
        switch value {
        case "course": setup = SetupPresentation(draft: .sample, step: .course)
        case "players": setup = SetupPresentation(draft: .sample, step: .players)
        case "games": setup = SetupPresentation(draft: .sample, step: .games)
        case "detail":
            guard let bridge = SharedEngine.bridge, let round = try? RoundDraft.sample.makeRound(using: bridge) else { return }
            modelContext.insert(round)
            try? modelContext.save()
            path = [round]
        default: break
        }
    }
    #endif
}
