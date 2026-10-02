import Foundation
import Testing
@testable import Wad

// MARK: - Filling the draft

struct RoundDraftCourseTests {
    @Test func aTeeFillsTheCourseFieldsAndEveryHole() throws {
        var draft = RoundDraft()
        let tee = try #require(CourseFixtures.oakGlen.tee(id: "male-blue"))
        try draft.fill(course: CourseFixtures.oakGlen, tee: tee)

        #expect(draft.courseName == "Oak Glen Golf Course")
        #expect(draft.ratingText == "71.3")
        #expect(draft.slopeText == "131")
        #expect(draft.holes.map(\.par) == CourseFixtures.pars)
        #expect(draft.holes.map(\.strokeIndexText) == CourseFixtures.strokeIndexes.map(String.init))
        #expect(draft.holes.map(\.number) == Array(1...18))
        #expect(draft.course == CourseSelection(
            courseID: CourseFixtures.oakGlenID,
            courseName: "Oak Glen Golf Course",
            teeID: "male-blue",
            teeName: "Blue",
            gender: .male
        ))
        #expect(draft.course?.teeText == "Blue tees (men's)")
        #expect(draft.courseIssues().isEmpty)
        #expect(draft.tee == Engine.TeeRating(slope: 131, courseRating: 71.3, par: 72))
        #expect(!draft.isCourseUntouched)
    }

    @Test func aTeeWithoutRatingLeavesRatingAndSlopeBlank() throws {
        var unrated = try #require(CourseFixtures.oakGlen.tee(id: "female-red"))
        unrated.courseRating = nil
        unrated.slope = nil
        var draft = RoundFixtures.ratedDraft()
        try draft.fill(course: CourseFixtures.oakGlen, tee: unrated)
        #expect(draft.ratingText.isEmpty)
        #expect(draft.slopeText.isEmpty)
        #expect(draft.tee == nil)
        #expect(draft.courseIssues().isEmpty)
        #expect(draft.course?.teeText == "Red tees (women's)")
    }

    @Test func aTeeWithoutStrokeIndexesOrEighteenHolesIsRefused() throws {
        var draft = RoundDraft()
        let junior = try #require(CourseFixtures.oakGlen.tee(id: "male-junior"))
        #expect(!junior.isSelectable)
        #expect(throws: CourseFillError.teeNotUsable("No stroke indexes")) {
            try draft.fill(course: CourseFixtures.oakGlen, tee: junior)
        }

        let nine = try #require(CourseFixtures.oakGlenExecutive.tees.first)
        #expect(throws: CourseFillError.teeNotUsable("9 holes")) {
            try draft.fill(course: CourseFixtures.oakGlenExecutive, tee: nine)
        }

        var misnumbered = try #require(CourseFixtures.oakGlen.tee(id: "male-blue"))
        misnumbered.holes[0].hole = 19
        #expect(throws: CourseFillError.self) {
            try draft.fill(course: CourseFixtures.oakGlen, tee: misnumbered)
        }

        // Nothing was changed by the refusals.
        #expect(draft.isCourseUntouched)
        #expect(draft.courseName.isEmpty)
        #expect(draft.course == nil)
    }

    @Test func theDefaultTeeIsTheFirstUsableMensTeeUnlessAnotherIsAsked() {
        let course = CourseFixtures.oakGlen
        #expect(course.defaultTee()?.teeId == "male-black")
        #expect(course.defaultTee(preferring: "female-red")?.teeId == "female-red")
        #expect(course.defaultTee(preferring: "male-junior")?.teeId == "male-black")
        #expect(course.defaultTee(preferring: "nope")?.teeId == "male-black")
        #expect(course.usableTees.count == 6)

        var womenOnly = course
        womenOnly.tees = course.tees(for: .female)
        #expect(womenOnly.defaultTee()?.teeId == "female-red")
        #expect(CourseFixtures.oakGlenExecutive.defaultTee() == nil)
    }

    @Test func anUntouchedCourseHasNothingTypedOrOnlyTheDefaultName() {
        var draft = RoundDraft()
        #expect(draft.isCourseUntouched)
        draft.courseName = CourseDefaults.courseName
        #expect(draft.isCourseUntouched)
        draft.courseName = "Pebble Beach"
        #expect(!draft.isCourseUntouched)

        draft = RoundDraft()
        draft.slopeText = "131"
        #expect(!draft.isCourseUntouched)
        draft = RoundDraft()
        draft.holes[2].par = 3
        #expect(!draft.isCourseUntouched)
        #expect(!RoundDraft.sample.isCourseUntouched)
    }
}

// MARK: - The course step

@MainActor
struct CourseStepModelTests {
    @Test func theDefaultCourseComesFromThePhoneWhenItIsThere() async throws {
        let service = FakeCourseLookupService()
        let cache = try CourseTestSupport.cache()
        // However old.
        cache.store(CourseFixtures.oakGlen, at: CourseTestSupport.now.addingTimeInterval(-90 * 24 * 60 * 60))
        let model = try CourseTestSupport.model(service: service, cache: cache)

        await model.loadDefaultCourse()
        #expect(model.defaultState == .ready(CourseFixtures.oakGlen))
        #expect(service.courseRequests.isEmpty)

        var draft = RoundDraft()
        #expect(model.applyDefault(to: &draft))
        #expect(draft.courseName == "Oak Glen Golf Course")
        #expect(draft.course?.teeID == "male-black")
        #expect(draft.ratingText == "73.1")
        #expect(draft.holes.map(\.par) == CourseFixtures.pars)
        #expect(model.course == CourseFixtures.oakGlen)
        #expect(model.selectedTeeID == "male-black")
        #expect(model.search.query == "Oak Glen Golf Course")
        #expect(model.memory.lastCourseID == CourseFixtures.oakGlenID)
        #expect(model.memory.lastTeeID == "male-black")

        // Once.
        var another = RoundDraft()
        #expect(!model.applyDefault(to: &another))
        #expect(another.isCourseUntouched)
        #expect(another.courseName.isEmpty)
    }

    @Test func theDefaultCourseIsFetchedOnceWhenThePhoneDoesNotHaveIt() async throws {
        let service = FakeCourseLookupService()
        let cache = try CourseTestSupport.cache()
        let model = try CourseTestSupport.model(service: service, cache: cache)

        var draft = RoundDraft()
        #expect(!model.applyDefault(to: &draft))
        await model.loadDefaultCourse()
        await model.loadDefaultCourse()
        #expect(service.courseRequests == [CourseFixtures.oakGlenID])
        #expect(cache.course(id: CourseFixtures.oakGlenID)?.value == CourseFixtures.oakGlen)
        #expect(model.applyDefault(to: &draft))
        #expect(draft.course?.courseID == CourseFixtures.oakGlenID)
        #expect(draft.courseIssues().isEmpty)
    }

    @Test func anUnavailableDefaultLeavesTheNameAndTheRestByHand() async throws {
        for error: CourseLookupError in [.offline, .rateLimited, .unavailable, .unauthorized] {
            let model = try CourseTestSupport.model(service: FakeCourseLookupService(error: error))
            await model.loadDefaultCourse()
            #expect(model.defaultState == .failed(error))

            var draft = RoundDraft()
            #expect(model.applyDefault(to: &draft))
            #expect(draft.courseName == "Oak Glen Golf Course")
            #expect(draft.course == nil)
            #expect(draft.holes == RoundDraft().holes)
            #expect(draft.ratingText.isEmpty && draft.slopeText.isEmpty)
            #expect(model.course == nil)
        }
    }

    @Test func withoutTheApiSettingsTheStepSaysSoAndWorksByHand() async throws {
        let service = FakeCourseLookupService(isConfigured: false, error: .notConfigured)
        let model = try CourseTestSupport.model(service: service)
        #expect(!model.isConfigured)
        await model.loadDefaultCourse()
        #expect(model.defaultState == .failed(.notConfigured))
        var draft = RoundDraft()
        model.applyDefault(to: &draft)
        #expect(draft.courseName == "Oak Glen Golf Course")
        #expect(draft.courseIssues() == [.strokeIndexMissing(holes: Array(1...18))])
    }

    @Test func aDraftWithEditsIsLeftAlone() async throws {
        let model = try CourseTestSupport.model()
        await model.loadDefaultCourse()
        var draft = RoundDraft()
        draft.courseName = "Pebble Beach"
        #expect(!model.applyDefault(to: &draft))
        #expect(draft.courseName == "Pebble Beach")
        #expect(draft.course == nil)

        var sample = RoundDraft.sample
        #expect(!model.applyDefault(to: &sample))
        #expect(sample.courseName == "Sample Links")
        #expect(sample.holes == RoundDraft.sample.holes)
        #expect(sample.course == nil)
    }

    @Test func theLastPickedCourseAndTeeAreTheNextDefault() async throws {
        let memory = CourseTestSupport.memory()
        memory.remember(courseID: CourseFixtures.stillwater.courseId, teeID: "female-red")
        let service = FakeCourseLookupService()
        let model = try CourseTestSupport.model(service: service, memory: memory)
        #expect(model.defaultCourseID == CourseFixtures.stillwater.courseId)

        await model.loadDefaultCourse()
        var draft = RoundDraft()
        #expect(model.applyDefault(to: &draft))
        #expect(service.courseRequests == [CourseFixtures.stillwater.courseId])
        #expect(draft.courseName == "Stillwater Country Club")
        #expect(draft.course?.teeID == "female-red")
        #expect(draft.ratingText == "71.1")
    }

    @Test func aDefaultCourseWithoutAUsableTeeFillsTheNameOnly() async throws {
        let memory = CourseTestSupport.memory()
        memory.remember(courseID: CourseFixtures.oakGlenExecutiveID, teeID: "male-white")
        let model = try CourseTestSupport.model(memory: memory)
        await model.loadDefaultCourse()
        var draft = RoundDraft()
        #expect(model.applyDefault(to: &draft))
        #expect(draft.courseName == "Oak Glen Golf Course - Executive Nine")
        #expect(draft.course == nil)
        #expect(draft.holes == RoundDraft().holes)
        #expect(model.course == CourseFixtures.oakGlenExecutive)
        #expect(model.selectedTeeID == nil)
    }

    @Test func pickingAResultLoadsTheCourseAndFillsItsDefaultTee() async throws {
        let service = FakeCourseLookupService()
        let model = try CourseTestSupport.model(service: service)
        model.search.query = "stillwater country"
        try await Task.sleep(for: .milliseconds(250))
        #expect(model.search.state == .results([CourseFixtures.stillwaterSummary]))

        #expect(await model.load(CourseFixtures.stillwaterSummary))
        #expect(model.detailState == .idle)
        #expect(model.course == CourseFixtures.stillwater)
        #expect(model.selectedTeeID == "male-blue")
        #expect(model.search.query == "Stillwater Country Club")
        #expect(model.search.state == .idle)

        var draft = RoundDraft()
        #expect(model.fill(&draft))
        #expect(draft.course?.courseID == CourseFixtures.stillwater.courseId)
        #expect(draft.ratingText == "72.0")
        #expect(draft.slopeText == "133")
        #expect(model.memory.lastCourseID == CourseFixtures.stillwater.courseId)

        // The pick is a fresh fetch; another trip to it is free.
        #expect(service.courseRequests == [CourseFixtures.stillwater.courseId])
        #expect(await model.load(CourseFixtures.stillwaterSummary))
        #expect(service.courseRequests == [CourseFixtures.stillwater.courseId])
    }

    @Test func aResultThatCannotBeLoadedShowsWhy() async throws {
        let service = FakeCourseLookupService()
        let model = try CourseTestSupport.model(service: service)
        service.error = .unavailable
        #expect(await model.load(CourseFixtures.oakGlenSummary) == false)
        #expect(model.detailState == .failed(.unavailable))
        #expect(model.course == nil)

        service.error = nil
        #expect(await model.load(CourseFixtures.oakGlenSummary))
        #expect(model.detailState == .idle)
    }

    @Test func pickingAnotherTeeRefillsAndAnUnusableTeeIsRefused() async throws {
        let model = try CourseTestSupport.model()
        #expect(await model.load(CourseFixtures.oakGlenSummary))
        var draft = RoundDraft()
        #expect(model.fill(&draft))
        #expect(draft.course?.teeID == "male-black")

        // The group corrects a value by hand; a new tee replaces it.
        draft.holes[0].par = 5
        #expect(model.select(teeID: "female-gold"))
        #expect(model.fill(&draft))
        #expect(draft.course?.teeID == "female-gold")
        #expect(draft.ratingText == "69.9")
        #expect(draft.slopeText == "121")
        #expect(draft.holes[0].par == 4)
        #expect(model.teeProblem == nil)
        #expect(model.memory.lastTeeID == "female-gold")

        #expect(!model.select(teeID: "male-junior"))
        #expect(model.selectedTeeID == "female-gold")
        #expect(model.teeProblem?.contains("No stroke indexes") == true)
        #expect(!model.select(teeID: "nope"))
    }

    @Test func nearMeRanksTheCachedCoursesAndNeverPicksOne() async throws {
        let cache = try CourseTestSupport.cache()
        var far = CourseFixtures.stillwater
        far.courseId = "far"
        far.location.latitude = 44.9
        var third = CourseFixtures.stillwater
        third.courseId = "third"
        third.location.longitude = -92.80
        var fourth = CourseFixtures.stillwater
        fourth.courseId = "fourth"
        fourth.location.longitude = -92.79
        for course in [far, fourth, third, CourseFixtures.stillwater, CourseFixtures.oakGlen] {
            cache.store(course, at: CourseTestSupport.now)
        }
        let fix = LocationFix(latitude: 45.0702, longitude: -92.8341)
        let model = try CourseTestSupport.model(cache: cache, location: FakeLocationProvider(result: .success(fix)))

        await model.findNearby()
        guard case .found(let nearby) = model.nearbyState else {
            Issue.record("\(model.nearbyState)")
            return
        }
        #expect(nearby.map(\.course.courseId) == [CourseFixtures.oakGlenID, CourseFixtures.stillwater.courseId, "third"])
        #expect(nearby.allSatisfy { $0.meters <= Double(CourseDistance.defaultRadiusMiles) * CourseDistance.metersPerMile })
        #expect(model.course == nil)
        #expect(model.selectedTeeID == nil)

        // Tapping a suggestion shows the course from the phone, with no request.
        var draft = RoundDraft()
        model.show(nearby[0].course)
        #expect(model.fill(&draft))
        #expect(draft.course?.courseID == CourseFixtures.oakGlenID)
    }

    @Test func nearMeSaysWhenThereIsNoLocationOrNoCourse() async throws {
        let denied = try CourseTestSupport.model(location: FakeLocationProvider(result: .failure(.denied)))
        await denied.findNearby()
        #expect(denied.nearbyState == .denied)

        let failed = try CourseTestSupport.model(location: FakeLocationProvider(result: .failure(.unavailable)))
        await failed.findNearby()
        #expect(failed.nearbyState == .failed)

        let elsewhere = try CourseTestSupport.model(location: FakeLocationProvider(result: .success(LocationFix(latitude: 0, longitude: 0))))
        await elsewhere.findNearby()
        #expect(elsewhere.nearbyState == .found([]))
    }
}
