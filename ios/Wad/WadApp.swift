import SwiftData
import SwiftUI

enum LaunchArgument {
    /// Keeps the store in memory, so every launch starts empty. Used by the UI tests.
    static let inMemoryStore = "-inMemoryStore"
    #if DEBUG
    /// `-debugStoreFile <name>` keeps the store in a file of its own in the
    /// temporary directory, so a UI test can relaunch the app on what it saved.
    static let debugStoreFile = "debugStoreFile"
    /// `-debugStoreCounts` shows how many rounds, holes, players and scores are stored.
    static let debugStoreCounts = "-debugStoreCounts"
    #endif
}

@main
struct WadApp: App {
    private let container: ModelContainer

    init() {
        let inMemory = ProcessInfo.processInfo.arguments.contains(LaunchArgument.inMemoryStore)
        var configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        #if DEBUG
        if let name = UserDefaults.standard.string(forKey: LaunchArgument.debugStoreFile) {
            configuration = ModelConfiguration(url: URL.temporaryDirectory.appending(path: "\(name).store"))
        }
        #endif
        do {
            container = try ModelContainer(for: Round.self, configurations: configuration)
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
