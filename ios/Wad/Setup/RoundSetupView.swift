import SwiftData
import SwiftUI

/// The engines, shared by the views. A JSContext must stay in one isolation
/// domain, so the bridge lives on the main actor.
@MainActor
enum SharedEngine {
    static let bridge: EngineBridge? = try? EngineBridge()
}

enum SetupStep: Int, CaseIterable, Sendable {
    case course, players, games

    var title: String {
        switch self {
        case .course: "Course"
        case .players: "Players"
        case .games: "Games"
        }
    }
}

/// New round: course, then players, then games. Creates the round at the end.
struct RoundSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.courseLookupService) private var courseLookupService

    @State var draft = RoundDraft()
    @State var step = SetupStep.course
    /// Lives for the whole flow, so a search survives a trip to the next step.
    @State private var courseModel: CourseStepModel?
    /// Issues are shown once the group has tried to move on from the step.
    @State private var showsIssues = false
    /// Counts the attempts to move on that the issues stopped.
    @State private var blockedAdvances = 0
    @State private var failure: String?

    let onCreate: (Round) -> Void

    private var issues: [SetupIssue] {
        switch step {
        case .course: draft.courseIssues()
        case .players: draft.playerIssues()
        case .games: draft.gameIssues()
        }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                form
                    .onChange(of: blockedAdvances) {
                        // The issues are at the end of the form, below the 18 holes of the course step.
                        guard let last = issues.last else { return }
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
            }
        }
        .interactiveDismissDisabled()
        .task {
            let model = courseModel ?? CourseStepModel(
                lookup: CourseLookup(service: courseLookupService, cache: CourseCache(context: modelContext))
            )
            courseModel = model
            await model.loadDefaultCourse()
            model.applyDefault(to: &draft)
        }
    }

    private var form: some View {
        Form {
            Group {
                switch step {
                case .course: CourseStepView(draft: $draft, model: courseModel)
                case .players: PlayersStepView(draft: $draft)
                case .games: GamesStepView(draft: $draft)
                }
            }
            .themedRows()

            if showsIssues, !issues.isEmpty {
                Section {
                    ForEach(Array(issues.enumerated()), id: \.element) { offset, issue in
                        Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.Palette.flagRed)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(issue.message)
                            .accessibilityIdentifier("setup.issue.\(offset + 1)")
                    }
                    .listRowBackground(WarningRowBackground())
                } header: {
                    SectionHeader("To fix", systemImage: "exclamationmark.triangle.fill")
                }
            }

            // After what is to fix, which the form scrolls to.
            if step == .players {
                VenmoHandlesStepView(draft: $draft)
                    .themedRows()
            }
        }
        .themedList()
        .safeAreaInset(edge: .top, spacing: 0) { SetupProgress(step: step) }
        .navigationTitle(step.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if let previous = SetupStep(rawValue: step.rawValue - 1) {
                    Button("Back") { move(to: previous) }
                } else {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(step == .games ? "Create" : "Next", action: advance)
            }
            #if DEBUG
            ToolbarItem(placement: .bottomBar) {
                Button("Fill sample") { draft = .sample }
            }
            #endif
        }
        .alert("Could not create the round", isPresented: .constant(failure != nil)) {
            Button("OK") { failure = nil }
        } message: {
            Text(failure ?? "")
        }
    }

    private func move(to step: SetupStep) {
        showsIssues = false
        self.step = step
    }

    private func advance() {
        guard issues.isEmpty else {
            showsIssues = true
            blockedAdvances += 1
            return
        }
        if let next = SetupStep(rawValue: step.rawValue + 1) {
            move(to: next)
        } else {
            create()
        }
    }

    private func create() {
        guard let bridge = SharedEngine.bridge else {
            failure = "The game engines could not be loaded."
            return
        }
        do {
            let round = try draft.makeRound(using: bridge)
            modelContext.insert(round)
            try modelContext.save()
            onCreate(round)
            dismiss()
        } catch SetupError.invalid(let issues) {
            failure = issues.map(\.message).joined(separator: "\n")
        } catch {
            failure = String(describing: error)
        }
    }
}

/// Where the group is in the setup: course, players, games.
struct SetupProgress: View {
    let step: SetupStep

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            ForEach(SetupStep.allCases, id: \.self) { other in
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Capsule()
                        .fill(other.rawValue <= step.rawValue ? Theme.Palette.fairway : Theme.Palette.rule)
                        .frame(height: 4)
                    Text(other.title)
                        .font(.caption.weight(other == step ? .bold : .regular))
                        .foregroundStyle(other == step ? Theme.Palette.ink : Theme.Palette.inkSecondary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, Theme.Spacing.s)
        .background(Theme.Palette.sand)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step.rawValue + 1) of \(SetupStep.allCases.count): \(step.title)")
    }
}

// MARK: - Course

struct CourseStepView: View {
    @Binding var draft: RoundDraft
    /// The lookup; nil only before the flow has set it up.
    var model: CourseStepModel?
    @FocusState private var focusedHole: Int?
    @State private var showsStrokeIndexOptions = false

    var body: some View {
        if let model {
            CourseSearchSection(draft: $draft, model: model)
        }

        Section {
            TextField("Course name", text: $draft.courseName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .accessibilityIdentifier("setup.courseName")
            NumberRow(title: "Rating", prompt: "Optional", text: $draft.ratingText, keyboard: .decimalPad)
            NumberRow(title: "Slope", prompt: "Optional", text: $draft.slopeText, keyboard: .numberPad)
            if let selection = draft.course {
                LabeledContent("Filled from", value: "\(selection.courseName), \(selection.teeText)")
                    .accessibilityIdentifier("setup.courseSelection")
            }
        } header: {
            SectionHeader("Course", systemImage: "map")
        } footer: {
            SectionFooter("With a rating and slope, course handicaps are computed from each player's handicap index.")
        }

        if let model, let course = model.course {
            CourseTeesSection(draft: $draft, model: model, course: course)
        }

        Section {
            Button("Stroke indexes", systemImage: "list.number") {
                showsStrokeIndexOptions = true
            }
            .accessibilityIdentifier("setup.strokeIndexes")
            .confirmationDialog("Stroke indexes", isPresented: $showsStrokeIndexOptions) {
                Button("Number 1 to 18 in order") {
                    for offset in draft.holes.indices {
                        draft.holes[offset].strokeIndexText = String(offset + 1)
                    }
                }
                Button("Clear all", role: .destructive) {
                    for offset in draft.holes.indices {
                        draft.holes[offset].strokeIndexText = ""
                    }
                }
            }

            HStack {
                Text("Hole").frame(width: 40, alignment: .leading)
                Text("Par").frame(maxWidth: .infinity)
                Text("Stroke index").frame(width: 100, alignment: .trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.Palette.inkSecondary)

            ForEach($draft.holes) { $hole in
                HStack {
                    Text("\(hole.number)")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Palette.fairway)
                        .frame(width: 40, alignment: .leading)
                    Picker("Par", selection: $hole.par) {
                        ForEach(Array(RoundDraft.parRange), id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityIdentifier("setup.hole.\(hole.number).par")
                    TextField("SI", text: $hole.strokeIndexText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(width: 60)
                        .focused($focusedHole, equals: hole.number)
                        .accessibilityIdentifier("setup.hole.\(hole.number).strokeIndex")
                }
                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
            }
            .environment(\.defaultMinListRowHeight, 38)
        } header: {
            SectionHeader("Holes", systemImage: "flag.fill")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                SectionFooter("Par \(draft.totalPar): out \(par(of: 1...9)), in \(par(of: 10...18)). Stroke index 1 is the hardest hole.")
                if !draft.unusedStrokeIndexes.isEmpty, draft.unusedStrokeIndexes.count < RoundDraft.holeCount {
                    SectionFooter("Not used yet: \(draft.unusedStrokeIndexes.map(String.init).joined(separator: ", "))")
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if let hole = focusedHole {
                    Button("Next hole") { focusedHole = hole < RoundDraft.holeCount ? hole + 1 : nil }
                }
                Spacer()
                Button("Done") {
                    focusedHole = nil
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
    }

    private func par(of holes: ClosedRange<Int>) -> Int {
        draft.holes.filter { holes.contains($0.number) }.reduce(0) { $0 + $1.par }
    }
}

// MARK: - Players

struct PlayersStepView: View {
    @Binding var draft: RoundDraft

    var body: some View {
        ForEach(draft.players) { player in
            let binding = binding(for: player)
            Section {
                TextField("Name", text: binding.name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("setup.player.\(number(of: player)).name")

                if draft.tee != nil {
                    NumberRow(
                        title: "Handicap index",
                        prompt: "15.4",
                        text: binding.handicapIndexText,
                        keyboard: .numbersAndPunctuation,
                        identifier: "setup.player.\(number(of: player)).handicapIndex"
                    )
                    LabeledContent("Computed course handicap", value: computedCourseHandicap(for: player))
                    Toggle("Override for this round", isOn: binding.overridesCourseHandicap)
                    if player.overridesCourseHandicap {
                        courseHandicapRow(binding)
                    }
                } else {
                    courseHandicapRow(binding)
                }

                // A row of its own: controls in a section header are not hittable for XCUITest on iOS 18.
                if draft.players.count > RoundDraft.playerCountRange.lowerBound {
                    Button("Remove player", systemImage: "minus.circle", role: .destructive) {
                        draft.players.removeAll { $0.id == player.id }
                    }
                    .accessibilityIdentifier("setup.player.\(number(of: player)).remove")
                }
            } header: {
                SectionHeader("Player \(number(of: player))", systemImage: "person.fill")
            }
        }

        Section {
            Button("Add player", systemImage: "plus") {
                draft.players.append(RoundDraft.Player())
            }
            .accessibilityIdentifier("setup.addPlayer")
            .disabled(draft.players.count >= RoundDraft.playerCountRange.upperBound)
        } footer: {
            if let tee = draft.tee {
                SectionFooter("Course handicaps use rating \(SetupText.display(handicapIndex: tee.courseRating)), slope \(tee.slope) and par \(tee.par). Write a plus handicap with a leading +.")
            } else {
                SectionFooter("The course has no rating and slope, so enter each player's course handicap for the round. Write a plus handicap with a leading +.")
            }
        }
    }

    /// Looks the player up by id. A binding into the array by position is read
    /// once more after its player was removed, which is out of range.
    private func binding(for player: RoundDraft.Player) -> Binding<RoundDraft.Player> {
        Binding {
            draft.players.first { $0.id == player.id } ?? player
        } set: { changed in
            guard let offset = draft.players.firstIndex(where: { $0.id == player.id }) else { return }
            draft.players[offset] = changed
        }
    }

    private func courseHandicapRow(_ player: Binding<RoundDraft.Player>) -> some View {
        NumberRow(
            title: "Course handicap",
            prompt: "Whole number",
            text: player.courseHandicapText,
            keyboard: .numbersAndPunctuation,
            identifier: "setup.player.\(number(of: player.wrappedValue)).courseHandicap"
        )
    }

    private func number(of player: RoundDraft.Player) -> Int {
        (draft.players.firstIndex { $0.id == player.id } ?? 0) + 1
    }

    private func computedCourseHandicap(for player: RoundDraft.Player) -> String {
        guard
            let bridge = SharedEngine.bridge,
            let value = try? draft.computedCourseHandicap(for: player, using: bridge)
        else { return "-" }
        return SetupText.display(courseHandicap: value)
    }
}

/// The players' optional Venmo handles. A section of its own at the end of
/// the players step, so that a player's section stays short.
struct VenmoHandlesStepView: View {
    @Binding var draft: RoundDraft

    var body: some View {
        Section {
            ForEach(Array(draft.players.enumerated()), id: \.element.venmoRowID) { offset, player in
                LabeledContent(player.trimmedName.isEmpty ? "Player \(offset + 1)" : player.trimmedName) {
                    TextField("Optional", text: binding(for: player))
                        .keyboardType(.asciiCapable)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("setup.player.\(offset + 1).venmoHandle")
                }
            }
        } header: {
            SectionHeader("Venmo handles", systemImage: "at")
        } footer: {
            SectionFooter("Optional, to pay or request with Venmo when the round is settled. They can be added later too.")
        }
    }

    private func binding(for player: RoundDraft.Player) -> Binding<String> {
        Binding {
            draft.players.first { $0.id == player.id }?.venmoHandleText ?? ""
        } set: { changed in
            guard let offset = draft.players.firstIndex(where: { $0.id == player.id }) else { return }
            draft.players[offset].venmoHandleText = changed
        }
    }
}

private extension RoundDraft.Player {
    /// The players' own ids are the ids of their sections in the same form.
    var venmoRowID: String { "venmo." + id }
}

// MARK: - Games

struct GamesStepView: View {
    @Binding var draft: RoundDraft

    var body: some View {
        Section {
            AmountRow(title: "Start value", identifier: "setup.amount.wadStart", text: $draft.wadStartText)
            AmountRow(title: "Step", identifier: "setup.amount.wadStep", text: $draft.wadStepText)
        } header: {
            SectionHeader("Wad", systemImage: "banknote")
        } footer: {
            SectionFooter("The first qualifying putt takes the Wad at the start value. Every make after that adds the step.")
        }

        Section {
            AmountRow(title: "Per skin", identifier: "setup.amount.skins", text: $draft.skinsBaseText)
        } header: {
            SectionHeader("Skins", systemImage: "dollarsign.circle")
        } footer: {
            SectionFooter("Net skins. A pushed hole carries its value to the next hole.")
        }

        Section {
            AmountRow(title: "Per greenie", identifier: "setup.amount.greenies", text: $draft.greeniesAmountText)
        } header: {
            SectionHeader("Greenies", systemImage: "flag.fill")
        } footer: {
            SectionFooter("Par 3s only. Every amount is collected from each other player.")
        }

        Section {
            Toggle("Start every hole at par", isOn: $draft.startsEveryHoleAtPar)
                .accessibilityIdentifier("setup.startsAtPar")
        } header: {
            SectionHeader("Scores", systemImage: "pencil.and.list.clipboard")
        } footer: {
            SectionFooter(
                "Every hole starts with par for each player. Change the scores as you play; "
                    + "the results count the pars on holes you have not played yet."
            )
        }
    }
}

// MARK: - Rows

struct NumberRow: View {
    let title: String
    let prompt: String
    @Binding var text: String
    let keyboard: UIKeyboardType
    var identifier: String?

    var body: some View {
        LabeledContent(title) {
            TextField(prompt, text: $text)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .accessibilityIdentifier(identifier ?? title)
        }
    }
}

struct AmountRow: View {
    let title: String
    let identifier: String
    @Binding var text: String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 2) {
                Text("$").foregroundStyle(Theme.Palette.inkSecondary)
                TextField("0.00", text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 90)
                    .accessibilityIdentifier(identifier)
            }
        }
    }
}

#if DEBUG
#Preview {
    RoundSetupView(draft: .sample, step: .players) { _ in }
        .modelContainer(WadSchema.previewContainer)
}
#endif
