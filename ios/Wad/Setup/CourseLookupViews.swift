import SwiftUI

/// Finding the course: the search field with its results, the courses near
/// the phone, and how the default course is doing. Without the API settings
/// it says so and leaves the step to the fields below.
struct CourseSearchSection: View {
    @Binding var draft: RoundDraft
    let model: CourseStepModel

    private var query: Binding<String> {
        Binding { model.search.query } set: { model.search.query = $0 }
    }

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
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.Palette.inkSecondary)
                .accessibilityHidden(true)
            TextField("Course or club name", text: query)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { Task { await model.search.searchNow() } }
                .accessibilityIdentifier("setup.courseSearch")
            if model.search.state == .searching {
                ProgressView()
            }
        }
    }

    @ViewBuilder
    private var searchRows: some View {
        switch model.search.state {
        case .idle, .searching:
            EmptyView()
        case .tooShort:
            StatusRow(CourseLookupError.queryTooShort.message, systemImage: "character.cursor.ibeam")
        case .results(let results):
            if results.isEmpty {
                StatusRow("No courses match.", systemImage: "questionmark.circle")
            } else {
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
        case .failed(let error):
            StatusRow(error.message, systemImage: "exclamationmark.triangle.fill", isProblem: true)
                .accessibilityIdentifier("setup.lookupStatus")
        }
        switch model.detailState {
        case .idle:
            EmptyView()
        case .loading(let summary):
            HStack {
                ProgressView()
                Text("Loading \(summary.displayName)")
                    .foregroundStyle(Theme.Palette.inkSecondary)
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
        switch model.nearbyState {
        case .idle, .locating:
            EmptyView()
        case .denied:
            StatusRow("Location is off for Wad. Allow it in Settings to see the courses near you.", systemImage: "location.slash")
        case .failed:
            StatusRow("Your location could not be found.", systemImage: "location.slash")
        case .found(let nearby):
            if nearby.isEmpty {
                StatusRow("No course looked up on this phone is within \(CourseDistance.text(meters: CourseDistance.nearbyMeters)).", systemImage: "location")
            } else {
                ForEach(nearby) { entry in
                    Button {
                        model.show(entry.course)
                        model.fill(&draft)
                    } label: {
                        CourseRow(summary: entry.course.summary, detail: "\(CourseDistance.text(meters: entry.meters)) away")
                    }
                    .accessibilityIdentifier("setup.nearby.\(entry.course.courseId)")
                }
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
                                .foregroundStyle(Theme.Palette.ink)
                            Text("\(tee.gender.title) - \(tee.ratingText) - par \(tee.par)")
                                .font(.caption)
                                .foregroundStyle(Theme.Palette.inkSecondary)
                        }
                        Spacer()
                        if let reason = tee.unavailableReason {
                            Text(reason)
                                .font(.caption)
                                .foregroundStyle(Theme.Palette.flagRed)
                        } else if tee.teeId == model.selectedTeeID {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.Palette.fairway)
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

private struct CourseRow: View {
    let summary: CourseSummary
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(summary.displayName)
                .foregroundStyle(Theme.Palette.ink)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSecondary)
            }
        }
    }
}

/// A row that says how the lookup is doing.
private struct StatusRow: View {
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
            .foregroundStyle(isProblem ? Theme.Palette.flagRed : Theme.Palette.inkSecondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
    }
}
