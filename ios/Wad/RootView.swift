import SwiftUI

/// Top-level tab shell. Courses and Profile are placeholders until their milestones land.
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
