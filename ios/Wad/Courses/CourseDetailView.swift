import SwiftUI

/// A course: where it is, its tees and the scorecard of the tee picked, and
/// the way into a round on it.
struct CourseDetailView: View {
    enum LoadState: Equatable {
        case loading
        case ready(Course)
        case failed(CourseLookupError)
    }

    let summary: CourseSummary
    let model: CoursesModel

    @Environment(AppNavigation.self) private var navigation: AppNavigation?
    @Environment(ProfileStore.self) private var profile: ProfileStore?
    @State private var state = LoadState.loading
    @State private var selectedTeeID: String?
    @State private var setup: RoundsView.SetupPresentation?
    @State private var problem: String?

    var body: some View {
        List {
            switch state {
            case .loading:
                Section {
                    HStack {
                        ProgressView()
                        Text("Loading \(summary.displayName)")
                            .foregroundStyle(Theme.Palette.ash)
                    }
                }
                .themedRows()
            case .failed(let error):
                Section {
                    StatusRow(error.message, systemImage: "exclamationmark.triangle.fill", isProblem: true)
                        .accessibilityIdentifier("course.lookupStatus")
                    Button("Try again") { Task { await load() } }
                }
                .themedRows()
            case .ready(let course):
                CourseDetailSections(
                    course: course,
                    selectedTeeID: $selectedTeeID,
                    problem: problem,
                    start: { tee in start(course: course, tee: tee) }
                )
            }
        }
        .themedList()
        .navigationTitle(summary.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(item: $setup) { setup in
            RoundSetupView(draft: setup.draft, step: setup.step) { round in
                navigation?.open(round)
            }
        }
    }

    private func load() async {
        state = .loading
        do {
            let course = try await model.course(for: summary)
            selectedTeeID = course.defaultTee(preferring: model.memory.lastTeeID)?.teeId ?? course.tees.first?.teeId
            state = .ready(course)
        } catch {
            state = .failed(error as? CourseLookupError ?? .unavailable)
        }
    }

    private func start(course: Course, tee: CourseTee) {
        do {
            let draft = try model.draft(for: course, tee: tee).prefilled(from: profile?.profile ?? Profile())
            setup = RoundsView.SetupPresentation(draft: draft, step: .course)
            problem = nil
        } catch CourseFillError.teeNotUsable(let reason) {
            problem = "\(tee.name) tees: \(reason)."
        } catch {
            problem = "\(tee.name) tees cannot be used."
        }
    }
}

/// The sections of a loaded course.
private struct CourseDetailSections: View {
    let course: Course
    @Binding var selectedTeeID: String?
    let problem: String?
    let start: (CourseTee) -> Void

    private var selectedTee: CourseTee? {
        selectedTeeID.flatMap(course.tee(id:))
    }

    var body: some View {
        Group {
            aboutSection
            teeSection
            if let tee = selectedTee {
                TeeScorecardSections(scorecard: TeeScorecard(tee: tee))
                startSection(tee)
            }
        }
        .themedRows()
    }

    private var aboutSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(course.displayName)
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(Theme.Palette.bone)
                    .accessibilityAddTraits(.isHeader)
                if course.clubName != course.courseName, !course.clubName.isEmpty {
                    Text(course.clubName)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.bone)
                }
                ForEach(addressLines, id: \.self) { line in
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.ash)
                }
            }
            .padding(.vertical, Theme.Spacing.xs)
            .accessibilityIdentifier("course.about")
        } header: {
            SectionHeader("Course", systemImage: "map")
        }
    }

    private var addressLines: [String] { course.location.addressLines }

    private var teeSection: some View {
        Section {
            Picker("Tee", selection: $selectedTeeID) {
                ForEach(course.tees) { tee in
                    Text(teeTitle(tee)).tag(Optional(tee.teeId))
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("course.tee")
            if let tee = selectedTee {
                LabeledContent("Rating / slope", value: tee.ratingText)
                LabeledContent("Par", value: "\(tee.par)")
                LabeledContent("Yardage", value: TeeScorecard.text(yards: tee.totalYards))
                if let reason = tee.unavailableReason {
                    StatusRow(
                        "\(reason): this tee cannot give handicap strokes, so a round cannot start on it.",
                        systemImage: "exclamationmark.triangle.fill",
                        isProblem: true
                    )
                    .accessibilityIdentifier("course.teeProblem")
                }
            }
        } header: {
            SectionHeader("Tee", systemImage: "flag.2.crossed")
        } footer: {
            if course.tees.isEmpty {
                SectionFooter("The provider lists no tees for this course.")
            }
        }
        .labeledContentStyle(ThemedLabeledContentStyle())
    }

    /// "Blue (men's)": tee names repeat across the genders.
    private func teeTitle(_ tee: CourseTee) -> String {
        "\(tee.name) (\(tee.gender == .male ? "men's" : "women's"))"
    }

    private func startSection(_ tee: CourseTee) -> some View {
        Section {
            Button("Start a round here") { start(tee) }
                .buttonStyle(.primary)
                .frame(maxWidth: .infinity)
                .disabled(!tee.isSelectable)
                .accessibilityIdentifier("course.start")
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            if let problem {
                StatusRow(problem, systemImage: "exclamationmark.triangle.fill", isProblem: true)
            }
        } footer: {
            SectionFooter("Opens a new round with this course and tee filled in. The players and games come next.")
        }
    }
}

/// The holes of the tee by nine, with each nine's totals and the card's.
private struct TeeScorecardSections: View {
    let scorecard: TeeScorecard

    var body: some View {
        if let back = scorecard.back {
            nine(scorecard.front, title: "Front nine")
            Section {
                headerRow
                holeRows(back)
                totalRow(title: back.title, par: back.par, yards: back.yardage)
                totalRow(title: "Total", par: scorecard.totalPar, yards: scorecard.totalYardage)
                    .accessibilityIdentifier("course.scorecard.total")
            } header: {
                SectionHeader("Back nine", systemImage: "flag.fill")
            }
            .environment(\.defaultMinListRowHeight, 32)
        } else {
            Section {
                headerRow
                holeRows(scorecard.front)
                totalRow(title: "Total", par: scorecard.totalPar, yards: scorecard.totalYardage)
                    .accessibilityIdentifier("course.scorecard.total")
            } header: {
                SectionHeader("Holes", systemImage: "flag.fill")
            }
            .environment(\.defaultMinListRowHeight, 32)
        }
    }

    private func nine(_ nine: TeeScorecard.Nine, title: String) -> some View {
        Section {
            headerRow
            holeRows(nine)
            totalRow(title: nine.title, par: nine.par, yards: nine.yardage)
        } header: {
            SectionHeader(title, systemImage: "flag.fill")
        }
        .environment(\.defaultMinListRowHeight, 32)
    }

    private var headerRow: some View {
        TeeScorecardRow(
            leading: Text("Hole"),
            par: Text("Par"),
            strokeIndex: Text("SI"),
            yards: Text("Yards")
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(Theme.Palette.ash)
        .accessibilityHidden(true)
    }

    private func holeRows(_ nine: TeeScorecard.Nine) -> some View {
        ForEach(nine.holes, id: \.hole) { hole in
            TeeScorecardRow(
                leading: Text("\(hole.hole)")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.Palette.blood),
                par: Text("\(hole.par)"),
                strokeIndex: Text(hole.strokeIndex.map(String.init) ?? "-"),
                yards: Text(hole.yardage.map(String.init) ?? "-")
            )
            .foregroundStyle(Theme.Palette.bone)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label(hole))
            .accessibilityIdentifier("course.scorecard.\(hole.hole)")
        }
    }

    private func label(_ hole: CourseHole) -> String {
        var parts = ["Hole \(hole.hole), par \(hole.par)"]
        if let strokeIndex = hole.strokeIndex { parts.append("stroke index \(strokeIndex)") }
        if let yardage = hole.yardage { parts.append("\(yardage) yards") }
        return parts.joined(separator: ", ")
    }

    private func totalRow(title: String, par: Int, yards: Int?) -> some View {
        TeeScorecardRow(
            leading: Text(title),
            par: Text("\(par)"),
            strokeIndex: Text(""),
            yards: Text(yards.map { $0.formatted(.number.grouping(.automatic)) } ?? "-")
        )
        .font(.body.weight(.bold))
        .foregroundStyle(Theme.Palette.bone)
        .emphasizedRows()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): par \(par)" + (yards.map { ", \($0) yards" } ?? ""))
    }
}

/// One line of the scorecard: the hole or a title, then par, stroke index and yards.
private struct TeeScorecardRow: View {
    let leading: Text
    let par: Text
    let strokeIndex: Text
    let yards: Text

    var body: some View {
        HStack {
            leading
                .frame(width: 56, alignment: .leading)
            par
                .frame(maxWidth: .infinity, alignment: .trailing)
            strokeIndex
                .frame(maxWidth: .infinity, alignment: .trailing)
            yards
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .monospacedDigit()
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }
}

#if DEBUG
#Preview {
    let container = WadSchema.previewContainer
    NavigationStack {
        CourseDetailView(
            summary: CourseFixtures.oakGlenSummary,
            model: CoursesModel(
                lookup: CourseLookup(service: FixtureCourseLookupService(), cache: CourseCache(context: container.mainContext))
            )
        )
    }
    .modelContainer(container)
}
#endif
