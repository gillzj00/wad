import SwiftData
import SwiftUI

enum LaunchArgument {
    /// Keeps the store in memory, so every launch starts empty. Used by the UI tests.
    static let inMemoryStore = "-inMemoryStore"
}

@main
struct WadApp: App {
    private let container: ModelContainer

    init() {
        let inMemory = ProcessInfo.processInfo.arguments.contains(LaunchArgument.inMemoryStore)
        do {
            container = try ModelContainer(
                for: Round.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory)
            )
        } catch {
            fatalError("Could not open the store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
