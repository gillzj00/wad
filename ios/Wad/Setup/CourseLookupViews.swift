import SwiftUI

/// Finding the course: the search field with its results, the courses near
/// the phone, and how the default course is doing. Without the API settings
/// it says so and leaves the step to the fields below.
struct CourseSearchSection: View {
    @Binding var draft: RoundDraft
    let model: CourseStepModel

    var body: some View {
        Section {
            if model.isConfigured {
                searchField
                searchRows
                nearMeButton
                nearbyRows
            } else {
                StatusRow(CourseLookupError.notConfigured.message, systemImage: "info.circle")
                    .accessibilityIdentifier("setup.lookupStatus")
            }
        } header: {
            SectionHeader("Find a course", systemImage: "magnifyingglass")
        } footer: {
            if model.isConfigured {
                SectionFooter(footerText)
            }
        }
    }

    private var searchField: some View {
        CourseSearchField(search: model.search, identifier: "setup.courseSearch")
    }

    @ViewBuilder
    private var searchRows: some View {
        CourseSearchStatus(state: model.search.state, identifier: "setup.lookupStatus")
        if case .results(let results) = model.search.state {
            ForEach(results) { summary in
                Button {
                    Task {
                        if await model.load(summary) { model.fill(&draft) }
                    }
                } label: {
                    CourseRow(summary: summary, detail: summary.location.cityState)
                }
                .accessibilityIdentifier("setup.course.\(summary.courseId)")
            }
        }
        switch model.detailState {
        case .idle:
            EmptyView()
        case .loading(let summary):
            HStack {
                ProgressView()
                Text("Loading \(summary.displayName)")
                    .foregroundStyle(Theme.Palette.ash)
            }
        case .failed(let error):
            StatusRow(error.message, systemImage: "exclamationmark.triangle.fill", isProblem: true)
                .accessibilityIdentifier("setup.lookupStatus")
        }
    }

    private var nearMeButton: some View {
        Button {
            Task { await model.findNearby() }
        } label: {
            HStack {
                Label("Near me", systemImage: "location")
                if model.nearbyState == .locating {
                    Spacer()
                    ProgressView()
                }
            }
        }
        .disabled(model.nearbyState == .locating)
        .accessibilityIdentifier("setup.nearMe")
    }

    @ViewBuilder
    private var nearbyRows: some View {
        NearbyStatus(state: model.nearbyState)
        if case .found(let nearby) = model.nearbyState {
            ForEach(nearby) { entry in
                Button {
                    model.show(entry.course)
                    model.fill(&draft)
                } label: {
                    CourseRow(summary: entry.course.summary, detail: entry.distanceText)
                }
                .accessibilityIdentifier("setup.nearby.\(entry.course.courseId)")
            }
        }
    }

    private var footerText: String {
        switch model.defaultState {
        case .idle, .ready:
            "Pick a course to fill in its tees, pars and stroke indexes, or enter them below."
        case .loading:
            "Looking up \(CourseDefaults.courseName)."
        case .failed(let error):
            "\(CourseDefaults.courseName) could not be looked up. \(error.message)"
        }
    }
}

/// The tees of the course that was picked. Picking one fills the course fields.
struct CourseTeesSection: View {
    @Binding var draft: RoundDraft
    let model: CourseStepModel
    let course: Course

    var body: some View {
        Section {
            ForEach(course.tees) { tee in
                Button {
                    if model.select(teeID: tee.teeId) { model.fill(&draft) }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tee.name)
                                .foregroundStyle(Theme.Palette.bone)
                            Text("\(tee.gender.title) - \(tee.ratingText) - par \(tee.par)")
                                .font(.caption)
                                .foregroundStyle(Theme.Palette.ash)
                        }
                        Spacer()
                        if let reason = tee.unavailableReason {
                            Text(reason)
                                .font(.caption)
                                .foregroundStyle(Theme.Palette.blood)
                        } else if tee.teeId == model.selectedTeeID {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.Palette.blood)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .disabled(!tee.isSelectable)
                .accessibilityIdentifier("setup.tee.\(tee.teeId)")
                .accessibilityAddTraits(tee.teeId == model.selectedTeeID ? .isSelected : [])
            }
            if let problem = model.teeProblem {
                StatusRow(problem, systemImage: "exclamationmark.triangle.fill", isProblem: true)
            }
        } header: {
            SectionHeader("Tees at \(course.displayName)", systemImage: "flag.2.crossed")
        } footer: {
            SectionFooter("A tee fills in the rating, slope, pars and stroke indexes below, which can still be changed. A tee without stroke indexes cannot give handicap strokes.")
        }
    }
}

/// The search field of a course lookup, which searches as the text is typed.
struct CourseSearchField: View {
    let search: CourseSearchModel
    let identifier: String

    private var query: Binding<String> {
        Binding { search.query } set: { search.query = $0 }
    }

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.Palette.ash)
                .accessibilityHidden(true)
            TextField("Course or club name", text: query, prompt: .prompt("Course or club name"))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { Task { await search.searchNow() } }
                .accessibilityIdentifier(identifier)
            if search.state == .searching {
                ProgressView()
            }
        }
    }
}

/// How the search is doing when it has no results to show: too short, no
/// match, or what went wrong. The results themselves are the caller's rows.
struct CourseSearchStatus: View {
    let state: CourseSearchModel.State
    let identifier: String

    var body: some View {
        switch state {
        case .idle, .searching:
            EmptyView()
        case .tooShort:
            StatusRow(CourseLookupError.queryTooShort.message, systemImage: "character.cursor.ibeam")
        case .results(let results):
            if results.isEmpty {
                StatusRow("No courses match.", systemImage: "questionmark.circle")
            }
        case .failed(let error):
            StatusRow(error.message, systemImage: "exclamationmark.triangle.fill", isProblem: true)
                .accessibilityIdentifier(identifier)
        }
    }
}

/// How "Near me" is doing when it has no courses to show.
struct NearbyStatus: View {
    let state: NearbyCoursesState

    var body: some View {
        switch state {
        case .idle, .locating:
            EmptyView()
        case .denied:
            StatusRow("Location is off for Wad. Allow it in Settings to see the courses near you.", systemImage: "location.slash")
        case .failed:
            StatusRow("Your location could not be found.", systemImage: "location.slash")
        case .found(let nearby):
            if nearby.isEmpty {
                StatusRow("No course looked up on this phone is within \(CourseDistance.text(meters: CourseDistance.nearbyMeters)).", systemImage: "location")
            }
        }
    }
}

extension CourseDistance.Nearby {
    /// "1.2 km away".
    var distanceText: String { "\(CourseDistance.text(meters: meters)) away" }
}

/// A course in a list: its name, with its town or its distance under it.
struct CourseRow: View {
    let summary: CourseSummary
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(summary.displayName)
                .foregroundStyle(Theme.Palette.bone)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.ash)
            }
        }
    }
}

/// A row that says how the lookup is doing.
struct StatusRow: View {
    let text: String
    let systemImage: String
    var isProblem = false

    init(_ text: String, systemImage: String, isProblem: Bool = false) {
        self.text = text
        self.systemImage = systemImage
        self.isProblem = isProblem
    }

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(isProblem ? Theme.Palette.blood : Theme.Palette.ash)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
    }
}
