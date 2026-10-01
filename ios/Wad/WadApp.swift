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
    /// `-debugColorScheme light|dark` shows the app in that color scheme.
    static let debugColorScheme = "debugColorScheme"
    /// `-debugCourseLookup fixture|off`: the course fixtures instead of the API, or
    /// no lookup at all, as in a build without the API settings.
    static let debugCourseLookup = "debugCourseLookup"
    #endif
}

@main
struct WadApp: App {
    private let container: ModelContainer

    init() {
        Appearance.apply()
        let inMemory = ProcessInfo.processInfo.arguments.contains(LaunchArgument.inMemoryStore)
        var configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        #if DEBUG
        if let name = UserDefaults.standard.string(forKey: LaunchArgument.debugStoreFile) {
            configuration = ModelConfiguration(url: URL.temporaryDirectory.appending(path: "\(name).store"))
        }
        #endif
        do {
            container = try ModelContainer(for: Schema(WadSchema.models), configurations: configuration)
        } catch {
            fatalError("Could not open the store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Theme.Palette.fairway)
                #if DEBUG
                .preferredColorScheme(Appearance.debugColorScheme)
                .environment(\.courseLookupService, Self.courseLookupService)
                #endif
        }
        .modelContainer(container)
    }

    #if DEBUG
    private static var courseLookupService: any CourseLookupService {
        switch UserDefaults.standard.string(forKey: LaunchArgument.debugCourseLookup) {
        case "fixture": FixtureCourseLookupService()
        case "off": CourseLookupClient(configuration: CourseLookupConfiguration(baseURL: nil, clientToken: ""))
        default: CourseLookupClient(configuration: .fromBundle)
        }
    }
    #endif
}
