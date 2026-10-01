import SwiftUI

/// Top-level tab shell. Courses and Profile are placeholders until their milestones land.
struct RootView: View {
    @State private var events = EventCenter()

    var body: some View {
        TabView {
            RoundsView()
                .tabItem { Label("Rounds", systemImage: "flag") }
            PlaceholderView(title: "Courses", message: "Course search arrives in M2.")
                .tabItem { Label("Courses", systemImage: "map") }
            PlaceholderView(title: "Profile", message: "Sign in and your handicap arrive in M1.")
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .overlay { EventOverlay() }
        .environment(events)
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
        events.enqueue(sample.events.filter { kinds.contains($0.kind) })
    }
    #endif
}

struct PlaceholderView: View {
    let title: String
    let message: String

    var body: some View {
        NavigationStack {
            EmptyStateView(title: title, message: message)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    RootView()
        .modelContainer(WadSchema.previewContainer)
}
