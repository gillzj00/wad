#if DEBUG
import Foundation

/// Courses in the API's shapes for the simulator and the tests, served by
/// `-debugCourseLookup fixture` instead of the API. Oak Glen (Stillwater, MN)
/// with the provider's real ids; the tees, ratings, pars, stroke indexes and
/// yardages are made up.
enum CourseFixtures {
    static let oakGlenID = CourseDefaults.courseID
    static let oakGlenExecutiveID = "gca-0zg07p94"

    static let oakGlenLocation = CourseLocation(
        address: "1599 McKusick Rd N",
        city: "Stillwater",
        state: "MN",
        country: "United States",
        latitude: 45.0702,
        longitude: -92.8341
    )

    static let pars = [4, 5, 4, 3, 4, 4, 3, 5, 4, 4, 3, 5, 4, 4, 3, 4, 5, 4]
    static let strokeIndexes = [9, 3, 7, 17, 1, 11, 15, 5, 13, 8, 18, 2, 10, 4, 16, 12, 6, 14]
    static let blackYards = [392, 541, 408, 176, 447, 384, 162, 530, 410, 401, 188, 522, 396, 433, 171, 388, 515, 404]

    static let oakGlenSummary = CourseSummary(
        courseId: oakGlenID,
        clubName: "Oak Glen Golf Course",
        courseName: "Oak Glen Golf Course",
        location: oakGlenLocation
    )

    static let oakGlenExecutiveSummary = CourseSummary(
        courseId: oakGlenExecutiveID,
        clubName: "Oak Glen Golf Course",
        courseName: "Executive Nine",
        location: oakGlenLocation
    )

    static let stillwaterSummary = CourseSummary(
        courseId: "gca-f1xtur3s",
        clubName: "Stillwater Country Club",
        courseName: "Stillwater Country Club",
        location: CourseLocation(
            address: "1421 4th St N",
            city: "Stillwater",
            state: "MN",
            country: "United States",
            latitude: 45.0665,
            longitude: -92.8150
        )
    )

    static let summaries = [oakGlenSummary, oakGlenExecutiveSummary, stillwaterSummary]

    /// The 18-hole course: four men's tees, two women's, and a junior tee
    /// without ratings or stroke indexes.
    static let oakGlen = Course(
        courseId: oakGlenID,
        clubName: oakGlenSummary.clubName,
        courseName: oakGlenSummary.courseName,
        location: oakGlenLocation,
        source: "golfcourseapi",
        scorecardUrl: nil,
        tees: [
            tee("Black", .male, rating: 73.1, slope: 136, yards: blackYards),
            tee("Blue", .male, rating: 71.3, slope: 131, yards: blackYards.map { $0 - 22 }),
            tee("White", .male, rating: 69.4, slope: 126, yards: blackYards.map { $0 - 48 }),
            tee("Gold", .male, rating: 67.0, slope: 119, yards: blackYards.map { $0 - 80 }),
            tee("Junior", .male, rating: nil, slope: nil, yards: blackYards.map { $0 - 150 }, strokeIndexes: nil),
            tee("Red", .female, rating: 72.4, slope: 128, yards: blackYards.map { $0 - 80 }),
            tee("Gold", .female, rating: 69.9, slope: 121, yards: blackYards.map { $0 - 110 }),
        ],
        fetchedAt: "2026-09-30T15:00:00.000Z"
    )

    /// The nine-hole course, which cannot fill an 18-hole round.
    static let oakGlenExecutive = Course(
        courseId: oakGlenExecutiveID,
        clubName: oakGlenExecutiveSummary.clubName,
        courseName: oakGlenExecutiveSummary.courseName,
        location: oakGlenLocation,
        source: "golfcourseapi",
        scorecardUrl: nil,
        tees: [
            CourseTee(
                teeId: "male-white",
                name: "White",
                gender: .male,
                courseRating: 28.4,
                slope: 88,
                par: 29,
                totalYards: 1_380,
                holes: (1...9).map { CourseHole(hole: $0, par: $0 == 5 ? 4 : 3, strokeIndex: $0, yardage: 120 + $0 * 10) },
                strokeIndexValid: true
            ),
        ],
        fetchedAt: "2026-09-30T15:00:00.000Z"
    )

    static let stillwater = Course(
        courseId: stillwaterSummary.courseId,
        clubName: stillwaterSummary.clubName,
        courseName: stillwaterSummary.courseName,
        location: stillwaterSummary.location,
        source: "golfcourseapi",
        scorecardUrl: nil,
        tees: [
            tee("Blue", .male, rating: 72.0, slope: 133, yards: blackYards.map { $0 - 10 }),
            tee("Red", .female, rating: 71.1, slope: 125, yards: blackYards.map { $0 - 90 }),
        ],
        fetchedAt: "2026-09-30T15:00:00.000Z"
    )

    static let courses = [oakGlen, oakGlenExecutive, stillwater]

    private static func tee(
        _ name: String,
        _ gender: TeeGender,
        rating: Double?,
        slope: Int?,
        yards: [Int],
        strokeIndexes: [Int]? = CourseFixtures.strokeIndexes
    ) -> CourseTee {
        CourseTee(
            teeId: "\(gender.rawValue)-\(name.lowercased())",
            name: name,
            gender: gender,
            courseRating: rating,
            slope: slope,
            par: pars.reduce(0, +),
            totalYards: yards.reduce(0, +),
            holes: (0..<18).map { CourseHole(hole: $0 + 1, par: pars[$0], strokeIndex: strokeIndexes?[$0], yardage: yards[$0]) },
            strokeIndexValid: strokeIndexes != nil
        )
    }
}

/// `-debugCourseLookup fixture`: the fixtures, with no network.
struct FixtureCourseLookupService: CourseLookupService {
    var isConfigured: Bool { true }

    func search(query: String) async throws -> [CourseSummary] {
        let words = CourseCache.normalize(query: query).split(separator: " ")
        return CourseFixtures.summaries.filter { summary in
            let haystack = [summary.clubName, summary.courseName, summary.location.city ?? ""].joined(separator: " ").lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
    }

    func course(id: String) async throws -> Course {
        guard let course = CourseFixtures.courses.first(where: { $0.courseId == id }) else { throw CourseLookupError.notFound }
        return course
    }
}
#endif
