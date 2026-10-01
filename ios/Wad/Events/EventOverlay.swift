import SwiftUI

/// The show over the whole screen while an event plays: the scene in a
/// Canvas driven by a TimelineView, the words over it. Tap to dismiss. Under
/// Reduce Motion the scene is one still picture.
struct EventOverlay: View {
    @Environment(EventCenter.self) private var center
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let event = center.current, center.settings.playback(reduceMotion: reduceMotion) != .off {
            EventStage(event: event, still: reduceMotion) { center.dismiss() }
                .id(event)
                .transition(.opacity)
        }
    }
}

struct EventStage: View {
    let event: GameEvent
    let still: Bool
    let dismiss: () -> Void

    @State private var start = Date()

    private var title: String { EventText.title(event) }
    private var subtitle: String { EventText.subtitle(event) }

    var body: some View {
        let scene = EventScenes.scene(for: event.kind)
        TimelineView(.animation(paused: still)) { timeline in
            let t = still ? scene.stillProgress : Anim.clamp(timeline.date.timeIntervalSince(start) / event.kind.duration)
            ZStack(alignment: .top) {
                Canvas(rendersAsynchronously: false) { context, size in
                    scene.draw(&context, size: size, t: t)
                }
                words(t: still ? 1 : t)
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(subtitle)")
        .accessibilityHint("Tap to dismiss")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("event.overlay")
        .task(id: event) {
            try? await Task.sleep(for: .seconds(event.kind.duration))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    /// The title slams in, the line under it follows.
    private func words(t: Double) -> some View {
        let pop = Anim.back(Anim.seg(t, 0.02, 0.2))
        let follow = Anim.easeOut(Anim.seg(t, 0.15, 0.35))
        return VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 54, weight: .black, design: .rounded))
                .textCase(.uppercase)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .scaleEffect(0.4 + 0.6 * pop)
                .opacity(pop)
            Text(subtitle)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
                .opacity(follow)
                .offset(y: 12 * (1 - follow))
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 2)
        .shadow(color: .black.opacity(0.6), radius: 14)
        .padding(.horizontal, 24)
        .padding(.top, 72)
        .frame(maxWidth: .infinity)
    }
}

#if DEBUG
#Preview("Hole in one") {
    EventStage(
        event: GameEvent(kind: .holeInOne, hole: 7, playerIDs: ["zach"], playerNames: ["Zach"]),
        still: false
    ) {}
}

#Preview("Birdie, still") {
    EventStage(
        event: GameEvent(kind: .birdie, hole: 2, playerIDs: ["zach"], playerNames: ["Zach"], otherNames: ["Sam", "Alex"]),
        still: true
    ) {}
}
#endif
