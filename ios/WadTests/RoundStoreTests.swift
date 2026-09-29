import Foundation
import SwiftData
import Testing
@testable import Wad

@MainActor
struct RoundStoreTests {
    @Test func savesAndFetchesARound() throws {
        let container = try ModelContainer(for: Round.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext

        context.insert(Round(courseName: "Pebble Beach"))
        try context.save()

        let rounds = try context.fetch(FetchDescriptor<Round>())
        #expect(rounds.map(\.courseName) == ["Pebble Beach"])
    }
}
