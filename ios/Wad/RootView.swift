import SwiftUI

enum AppTab: Hashable {
    case rounds, courses, profile
}

/// The tab shown, a round created on another tab that the Rounds tab opens
/// when it comes back on screen, and a screen for the Rounds tab to push from
/// a screen that has no hold on its path.
@MainActor
@Observable
final class AppNavigation {
    var tab = AppTab.rounds
    var roundToOpen: Round?
    var pendingRoute: RoundsRoute?

    /// Shows the round on the Rounds tab.
    func open(_ round: Round) {
        roundToOpen = round
        tab = .rounds
    }

    /// Pushes the screen on the Rounds tab.
    func push(_ route: RoundsRoute) {
        pendingRoute = route
    }
}

/// Top-level tab shell.
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var events: EventCenter
    @State private var live: LiveCenter
    @State private var navigation = AppNavigation()
    @State private var profile: ProfileStore

    init() {
        let events = EventCenter()
        _events = State(initialValue: events)
        _live = State(initialValue: LiveCenter(events: events))
        _profile = State(initialValue: ProfileStore(defaults: ProfileStore.launchDefaults()))
    }

    var body: some View {
        @Bindable var navigation = navigation
        TabView(selection: $navigation.tab) {
            RoundsView()
                .tabItem { Label("Rounds", systemImage: "flag") }
                .tag(AppTab.rounds)
            CoursesView()
                .tabItem { Label("Courses", systemImage: "map") }
                .tag(AppTab.courses)
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
        .overlay { EventOverlay() }
        .environment(events)
        .environment(live)
        .environment(navigation)
        .environment(profile)
        // A connection suspended in the background is made again on return.
        .onChange(of: scenePhase) { previous, phase in
            if phase == .active, previous == .background {
                live.didReturnToForeground()
            }
        }
        #if DEBUG
        .task { playDebugEvents() }
        #endif
    }

    #if DEBUG
    /// `-debugEvents birdie,eagle,...`: the named shows, in that order, on a
    /// sample round's players. For simulator screenshots.
    private func playDebugEvents() {
        guard let names = UserDefaults.standard.string(forKey: LaunchArgument.debugEvents) else { return }
        let kinds: [GameEventKind] = names.split(separator: ",").compactMap { name in
            GameEventKind.allCases.first { "\($0)" == name }
        }
        var sample = GameSnapshot(players: [
            GameSnapshot.Player(id: "zach", name: "Zach"),
            GameSnapshot.Player(id: "sam", name: "Sam"),
            GameSnapshot.Player(id: "alex", name: "Alex"),
        ])
        sample.greenieAmountCents = 500
        for kind in kinds {
            switch kind {
            case .holeInOne: sample.scores.append(GameSnapshot.Score(playerID: "zach", hole: 3, par: 3, gross: 1))
            case .albatross: sample.scores.append(GameSnapshot.Score(playerID: "zach", hole: 2, par: 5, gross: 2))
            case .eagle: sample.scores.append(GameSnapshot.Score(playerID: "sam", hole: 7, par: 5, gross: 3))
            case .birdie: sample.scores.append(GameSnapshot.Score(playerID: "zach", hole: 1, par: 4, gross: 3))
            case .snowman: sample.scores.append(GameSnapshot.Score(playerID: "alex", hole: 5, par: 4, gross: 8))
            case .greenie: sample.greenieWins.append(GameSnapshot.GreenieWin(hole: 3, winnerID: "zach"))
            case .wadTaken: sample.wadMakes.append(GameSnapshot.WadMake(hole: 4, playerID: "sam", valueCents: 900))
            case .skinWon: sample.skinWins.append(GameSnapshot.SkinWin(hole: 4, winnerID: "alex", atStakeCents: 1500))
            case .wolfHoleWon: sample.wolfWins.append(GameSnapshot.WolfWin(hole: 6, winnerIDs: ["zach", "sam"]))
            }
        }
        // Events play only on a hole every player has scored: the others make par.
        for (hole, par) in [1: 4, 2: 5, 3: 3, 4: 4, 5: 4, 6: 4, 7: 5].sorted(by: { $0.key < $1.key }) {
            for player in sample.players where !sample.scores.contains(where: { $0.hole == hole && $0.playerID == player.id }) {
                sample.scores.append(GameSnapshot.Score(playerID: player.id, hole: hole, par: par, gross: par))
            }
        }
        events.enqueue(sample.events.filter { kinds.contains($0.kind) })
    }
    #endif
}

#Preview {
    RootView()
        .modelContainer(WadSchema.previewContainer)
}
