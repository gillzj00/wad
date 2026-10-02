import SwiftData
import SwiftUI

/// The Courses tab: find a course, read its scorecard, start a round on it.
/// Reuses the lookup of the course step: the same client and the same cache.
struct CoursesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.courseLookupService) private var courseLookupService
    @State private var model: CoursesModel?
    @State private var path: [CourseSummary] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let model {
                    CoursesList(model: model)
                } else {
                    Theme.Palette.charcoal.ignoresSafeArea()
                }
            }
            .navigationTitle("Courses")
            .navigationDestination(for: CourseSummary.self) { summary in
                if let model {
                    CourseDetailView(summary: summary, model: model)
                }
            }
        }
        .task {
            if model == nil {
                model = CoursesModel(
                    lookup: CourseLookup(service: courseLookupService, cache: CourseCache(context: modelContext))
                )
            }
            model?.refreshRecent()
        }
    }
}

/// The search, the courses near the phone and the courses on it.
private struct CoursesList: View {
    let model: CoursesModel

    var body: some View {
        List {
            Group {
                findSection
                recentSection
            }
            .themedRows()
        }
        .themedList()
        .onAppear { model.refreshRecent() }
    }

    private var findSection: some View {
        Section {
            if model.isConfigured {
                CourseSearchField(search: model.search, identifier: "courses.search")
                CourseSearchStatus(state: model.search.state, identifier: "courses.lookupStatus")
                if case .results(let results) = model.search.state {
                    ForEach(results) { summary in
                        NavigationLink(value: summary) {
                            CourseRow(summary: summary, detail: summary.location.cityState)
                        }
                        .accessibilityIdentifier("courses.result.\(summary.courseId)")
                    }
                }
                nearMeButton
                NearbyRadiusPicker(miles: model.nearbyRadiusMiles, identifier: "courses.nearbyRadius") { miles in
                    Task { await model.setNearbyRadius(miles) }
                }
                NearbyStatus(state: model.nearbyState, radiusMiles: model.nearbyRadiusMiles)
                if case .found(let nearby) = model.nearbyState {
                    ForEach(nearby) { entry in
                        NavigationLink(value: entry.course.summary) {
                            CourseRow(summary: entry.course.summary, detail: entry.distanceText)
                        }
                        .accessibilityIdentifier("courses.nearby.\(entry.course.courseId)")
                    }
                }
            } else {
                StatusRow(
                    "Course lookup is not configured in this build. The courses already on this phone are listed below.",
                    systemImage: "info.circle"
                )
                .accessibilityIdentifier("courses.lookupStatus")
            }
        } header: {
            SectionHeader("Find a course", systemImage: "magnifyingglass")
        } footer: {
            if model.isConfigured {
                SectionFooter("Search by course or club name, or list the courses on this phone near you.")
            }
        }
    }

    private var recentSection: some View {
        Section {
            if model.recent.isEmpty {
                StatusRow("No course has been looked up on this phone yet.", systemImage: "clock")
            } else {
                ForEach(model.recent) { course in
                    NavigationLink(value: course.summary) {
                        CourseRow(summary: course.summary, detail: course.location.cityState)
                    }
                    .accessibilityIdentifier("courses.recent.\(course.courseId)")
                }
            }
        } header: {
            SectionHeader("Recent", systemImage: "clock")
        } footer: {
            SectionFooter("Every course looked up is kept on this phone, so its scorecard and a round on it work offline.")
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
        .accessibilityIdentifier("courses.nearMe")
    }
}

#Preview {
    CoursesView()
        .modelContainer(WadSchema.previewContainer)
}
