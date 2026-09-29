import SwiftData
import SwiftUI

@main
struct WadApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: Round.self)
    }
}
