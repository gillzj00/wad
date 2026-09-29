import Foundation
import SwiftData

/// Local copy of a round. The offline-first store is the working copy during
/// play and syncs to the backend (docs/architecture.md). Fields grow in M3.
@Model
final class Round {
    @Attribute(.unique) var id: UUID
    var courseName: String
    var startedAt: Date

    init(id: UUID = UUID(), courseName: String, startedAt: Date = .now) {
        self.id = id
        self.courseName = courseName
        self.startedAt = startedAt
    }
}
