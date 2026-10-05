import SwiftUI
import UIKit

// MARK: - Sharing (round detail)

/// The Live section of a round: share it under a code, or the code, the
/// connection and the way to stop while it is shared.
struct LiveShareSection: View {
    let round: Round

    @Environment(LiveCenter.self) private var live: LiveCenter?

    var body: some View {
        Section {
            if let live, live.isConfigured {
                if live.isSharing(round.liveCode), let code = live.code {
                    LiveCodeRow(code: code)
                    LiveStateRow(state: live.state)
                    Button("Stop sharing", systemImage: "stop.circle", role: .destructive) {
                        live.stop()
                    }
                    .accessibilityIdentifier("live.stop")
                } else {
                    Button {
                        share(live)
                    } label: {
                        Label("Share live", systemImage: "dot.radiowaves.left.and.right")
                            .font(.headline)
                    }
                    .accessibilityIdentifier("live.share")
                }
            } else {
                StatusRow("Live sharing is not configured in this build.", systemImage: "info.circle")
                    .accessibilityIdentifier("live.state")
            }
        } header: {
            SectionHeader("Live", systemImage: "dot.radiowaves.left.and.right")
        } footer: {
            if let live, live.isConfigured {
                SectionFooter(
                    "The phones that follow the code see every birdie, eagle, skin, Wad, greenie and Wolf hole as it is scored here. "
                        + "Anyone with the code can follow."
                )
            }
        }
    }

    /// The round keeps its code, so sharing it again gives the followers the same one.
    private func share(_ live: LiveCenter) {
        let code = round.liveCode.flatMap { LiveCode.isValid($0) ? $0 : nil } ?? LiveCode.generate()
        round.liveCode = code
        try? round.modelContext?.save()
        live.share(code: code)
    }
}

/// The code, large enough to read across a cart, with a copy button.
struct LiveCodeRow: View {
    let code: String

    @State private var copied = false

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            Text(code)
                .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                .tracking(4)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(Theme.Palette.bone)
                .accessibilityLabel("Code \(code.map(String.init).joined(separator: " "))")
                .accessibilityIdentifier("live.code")
            Spacer(minLength: 0)
            Button {
                UIPasteboard.general.string = code
                copied = true
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.secondary)
            .accessibilityIdentifier("live.copy")
            .task(id: copied) {
                guard copied else { return }
                try? await Task.sleep(for: .seconds(2))
                copied = false
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}

/// How the connection is doing, in words.
struct LiveStateRow: View {
    let state: LiveSession.State

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Label(Self.text(state), systemImage: Self.symbol(state))
                .font(.subheadline)
                .foregroundStyle(Self.color(state))
            if state == .connecting {
                Spacer()
                ProgressView()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.text(state))
        .accessibilityIdentifier("live.state")
    }

    static func text(_ state: LiveSession.State) -> String {
        switch state {
        case .idle: "Not connected."
        case .connecting: "Connecting."
        case .connected: "Connected, joining the round."
        case .subscribed(let members):
            members <= 1 ? "Live. No other phone is connected yet." : "Live. \(members) phones connected."
        case .failed(let reason): reason
        }
    }

    private static func symbol(_ state: LiveSession.State) -> String {
        switch state {
        case .idle, .connecting, .connected: "dot.radiowaves.left.and.right"
        case .subscribed: "dot.radiowaves.left.and.right"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private static func color(_ state: LiveSession.State) -> Color {
        switch state {
        case .subscribed: Theme.Palette.ember
        case .failed: Theme.Palette.blood
        case .idle, .connecting, .connected: Theme.Palette.ash
        }
    }
}

// MARK: - Following (Rounds tab)

/// Type the scoring phone's code and follow it: the connection, the code and
/// the feed of what it scores. The following goes on when the sheet closes.
struct LiveFollowView: View {
    @Environment(LiveCenter.self) private var live: LiveCenter?
    @Environment(\.dismiss) private var dismiss

    @State private var input = ""

    var body: some View {
        NavigationStack {
            List {
                Group {
                    if let live, live.isConfigured {
                        if live.role == .following, let code = live.code {
                            following(live, code: code)
                        } else {
                            codeEntry(live)
                        }
                    } else {
                        Section {
                            StatusRow("Live following is not configured in this build.", systemImage: "info.circle")
                                .accessibilityIdentifier("live.state")
                        }
                    }
                }
                .themedRows()
            }
            .themedList()
            .navigationTitle("Follow a round")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("live.done")
                }
            }
        }
    }

    private func codeEntry(_ live: LiveCenter) -> some View {
        Section {
            TextField(text: $input, prompt: Text.prompt("ABC123")) {
                Text("Code")
            }
            .font(.system(.title2, design: .monospaced, weight: .bold))
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .keyboardType(.asciiCapable)
            .submitLabel(.go)
            .onChange(of: input) { _, value in
                let normalized = String(LiveCode.normalize(value).prefix(LiveCode.length))
                if normalized != value {
                    input = normalized
                }
            }
            .onSubmit { follow(live) }
            .accessibilityIdentifier("live.codeField")
            Button {
                follow(live)
            } label: {
                Label("Follow", systemImage: "dot.radiowaves.left.and.right")
                    .font(.headline)
            }
            .disabled(!LiveCode.isValid(input))
            .accessibilityIdentifier("live.followButton")
        } header: {
            SectionHeader("Code", systemImage: "number")
        } footer: {
            SectionFooter("The 6-character code is in the Live section of the round on the phone that scores it.")
        }
    }

    private func follow(_ live: LiveCenter) {
        let code = LiveCode.normalize(input)
        guard LiveCode.isValid(code) else { return }
        live.follow(code: code)
    }

    @ViewBuilder
    private func following(_ live: LiveCenter, code: String) -> some View {
        Section {
            LiveCodeRow(code: code)
            LiveStateRow(state: live.state)
            Button("Stop following", systemImage: "stop.circle", role: .destructive) {
                live.stop()
            }
            .accessibilityIdentifier("live.stopFollowing")
        } header: {
            SectionHeader("Following", systemImage: "dot.radiowaves.left.and.right")
        } footer: {
            SectionFooter("Every event the scoring phone records plays here, wherever you are in the app.")
        }

        Section {
            if live.feed.isEmpty {
                StatusRow("Nothing yet. Scores and events appear here as they are entered.", systemImage: "clock")
                    .accessibilityIdentifier("live.feed")
            } else {
                ForEach(live.feed) { entry in
                    if let line = LiveFeedText.line(entry.payload) {
                        LiveFeedRow(line: line, at: entry.receivedAt)
                            .accessibilityIdentifier("live.feed")
                    }
                }
            }
        } header: {
            SectionHeader("Feed", systemImage: "list.bullet")
        }
    }
}

/// One line of the feed: what happened and when it arrived.
struct LiveFeedRow: View {
    let line: LiveFeedText.Line
    let at: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.bone)
                Text(line.detail)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.ash)
            }
            Spacer(minLength: 0)
            Text(at, format: .dateTime.hour().minute())
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.ash)
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Follow") {
    LiveFollowView()
        .environment(LiveCenter(
            configuration: LiveConfiguration(url: URL(string: "wss://example.test"), clientToken: "token"),
            events: EventCenter()
        ))
}
#endif
