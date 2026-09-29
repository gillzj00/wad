import SwiftUI

/// Top-level tab shell. Each tab is a placeholder until its milestone lands.
struct RootView: View {
    var body: some View {
        TabView {
            RoundsView()
                .tabItem { Label("Rounds", systemImage: "flag") }
            PlaceholderView(title: "Courses", message: "Course search arrives in M2.")
                .tabItem { Label("Courses", systemImage: "map") }
            PlaceholderView(title: "Profile", message: "Sign in and your handicap arrive in M1.")
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
    }
}

struct RoundsView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("No rounds yet", systemImage: "flag", description: Text("Rounds arrive in M3."))
                .navigationTitle("Rounds")
        }
    }
}

struct PlaceholderView: View {
    let title: String
    let message: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: "hammer", description: Text(message))
                .navigationTitle(title)
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: Round.self, inMemory: true)
}
