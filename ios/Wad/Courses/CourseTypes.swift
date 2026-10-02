import Foundation

// The courses API's shapes (backend/src/shared/types.ts, docs/api.md Courses).
// Decoded as the API sends them; nothing is renamed.

enum TeeGender: String, Codable, Sendable, CaseIterable {
    case male, female

    var title: String {
        switch self {
        case .male: "Men's tees"
        case .female: "Women's tees"
        }
    }
}

struct CourseLocation: Codable, Hashable, Sendable {
    var address: String?
    var city: String?
    var state: String?
    var country: String?
    var latitude: Double?
    var longitude: Double?

    /// "Stillwater, MN", or whichever of the two is known.
    var cityState: String? {
        let parts = [city, state].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

struct CourseSummary: Codable, Hashable, Identifiable, Sendable {
    var courseId: String
    var clubName: String
    var courseName: String
    var location: CourseLocation

    var id: String { courseId }

    /// The course as the round names it: the course name, with the club's
    /// name in front when it says something more.
    var displayName: String {
        let club = clubName.trimmingCharacters(in: .whitespaces)
        let course = courseName.trimmingCharacters(in: .whitespaces)
        if course.isEmpty { return club }
        if club.isEmpty || course.localizedCaseInsensitiveContains(club) { return course }
        return "\(club) - \(course)"
    }
}

struct CourseHole: Codable, Equatable, Sendable {
    var hole: Int
    var par: Int
    var strokeIndex: Int?
    var yardage: Int?
}

struct CourseTee: Codable, Equatable, Identifiable, Sendable {
    var teeId: String
    var name: String
    var gender: TeeGender
    var courseRating: Double?
    var slope: Int?
    var par: Int
    var totalYards: Int?
    var holes: [CourseHole]
    /// Every hole has a stroke index and they are unique, so handicaps can be allocated.
    var strokeIndexValid: Bool

    var id: String { teeId }

    /// A round is 18 holes with a stroke index on each; a tee without them is
    /// shown but cannot fill the round's course.
    var isSelectable: Bool { strokeIndexValid && holes.count == RoundDraft.holeCount }

    /// Why the tee cannot be selected, for its row.
    var unavailableReason: String? {
        if holes.count != RoundDraft.holeCount { return "\(holes.count) holes" }
        if !strokeIndexValid { return "No stroke indexes" }
        return nil
    }

    /// "73.1 / 136" or "Not rated".
    var ratingText: String {
        guard let courseRating, let slope else { return "Not rated" }
        return "\(SetupText.display(handicapIndex: courseRating)) / \(slope)"
    }
}

struct Course: Codable, Equatable, Identifiable, Sendable {
    var courseId: String
    var clubName: String
    var courseName: String
    var location: CourseLocation
    var source: String
    var scorecardUrl: String?
    var tees: [CourseTee]
    /// ISO timestamp of when the data was fetched or entered.
    var fetchedAt: String

    var id: String { courseId }

    var summary: CourseSummary {
        CourseSummary(courseId: courseId, clubName: clubName, courseName: courseName, location: location)
    }

    var displayName: String { summary.displayName }

    /// The tees of one gender, in the API's order.
    func tees(for gender: TeeGender) -> [CourseTee] {
        tees.filter { $0.gender == gender }
    }

    func tee(id: String) -> CourseTee? {
        tees.first { $0.teeId == id }
    }
}

// MARK: - Responses

struct CourseSearchResponse: Codable, Sendable {
    var courses: [CourseSummary]
}

struct CourseResponse: Codable, Sendable {
    var course: Course
}

struct CourseErrorResponse: Codable, Sendable {
    struct Body: Codable, Sendable {
        var code: String
        var message: String
    }

    var error: Body
}
