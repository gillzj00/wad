import Foundation
import SwiftData

/// Every model of the app's store. The course cache is not related to the
/// rounds, so it has to be listed for the container.
enum WadSchema {
    static let models: [any PersistentModel.Type] = [
        Round.self, RoundHole.self, RoundPlayer.self, HoleScore.self, PaidMarker.self,
        CachedCourse.self, CachedCourseSearch.self,
    ]
}

/// A course looked up on this phone, as the API sent it, so that the round
/// can be set up on it again without the API: offline, or without spending
/// one of the provider's few daily requests.
@Model
final class CachedCourse {
    @Attribute(.unique) var courseID: String
    /// The `Course` as JSON.
    var json: Data
    var cachedAt: Date

    init(courseID: String, json: Data, cachedAt: Date) {
        self.courseID = courseID
        self.json = json
        self.cachedAt = cachedAt
    }
}

/// The results of a search, by its normalized query.
@Model
final class CachedCourseSearch {
    @Attribute(.unique) var query: String
    /// The `[CourseSummary]` as JSON.
    var json: Data
    var cachedAt: Date

    init(query: String, json: Data, cachedAt: Date) {
        self.query = query
        self.json = json
        self.cachedAt = cachedAt
    }
}

/// A cached value with when it was cached.
struct CachedEntry<Value: Equatable>: Equatable {
    let value: Value
    let cachedAt: Date

    func isFresh(at now: Date) -> Bool {
        now.timeIntervalSince(cachedAt) < CourseCache.expiry
    }
}

/// The on-device cache of courses and searches, in the app's store.
@MainActor
struct CourseCache {
    /// The API caches for 7 days too (docs/api.md).
    nonisolated static let expiry: TimeInterval = 7 * 24 * 60 * 60

    let context: ModelContext

    /// The API's normalization: trimmed, lowercased, one space between words.
    nonisolated static func normalize(query: String) -> String {
        query.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    func course(id: String) -> CachedEntry<Course>? {
        guard let cached = try? context.fetch(FetchDescriptor<CachedCourse>(predicate: #Predicate { $0.courseID == id })).first,
              let course = try? JSONDecoder().decode(Course.self, from: cached.json)
        else { return nil }
        return CachedEntry(value: course, cachedAt: cached.cachedAt)
    }

    func results(query: String) -> CachedEntry<[CourseSummary]>? {
        let key = Self.normalize(query: query)
        guard let cached = try? context.fetch(FetchDescriptor<CachedCourseSearch>(predicate: #Predicate { $0.query == key })).first,
              let results = try? JSONDecoder().decode([CourseSummary].self, from: cached.json)
        else { return nil }
        return CachedEntry(value: results, cachedAt: cached.cachedAt)
    }

    func store(_ course: Course, at now: Date) {
        guard let json = try? JSONEncoder().encode(course) else { return }
        let id = course.courseId
        if let existing = try? context.fetch(FetchDescriptor<CachedCourse>(predicate: #Predicate { $0.courseID == id })).first {
            existing.json = json
            existing.cachedAt = now
        } else {
            context.insert(CachedCourse(courseID: id, json: json, cachedAt: now))
        }
        try? context.save()
    }

    func store(_ results: [CourseSummary], query: String, at now: Date) {
        guard let json = try? JSONEncoder().encode(results) else { return }
        let key = Self.normalize(query: query)
        if let existing = try? context.fetch(FetchDescriptor<CachedCourseSearch>(predicate: #Predicate { $0.query == key })).first {
            existing.json = json
            existing.cachedAt = now
        } else {
            context.insert(CachedCourseSearch(query: key, json: json, cachedAt: now))
        }
        try? context.save()
    }

    /// Every course on the phone, whatever its age.
    func courses() -> [Course] {
        let cached = (try? context.fetch(FetchDescriptor<CachedCourse>(sortBy: [SortDescriptor(\.cachedAt, order: .reverse)]))) ?? []
        return cached.compactMap { try? JSONDecoder().decode(Course.self, from: $0.json) }
    }
}
