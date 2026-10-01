import SpriteKit
import SwiftUI

/// The show over the whole screen while an event plays: its SpriteKit scene
/// with the headline over it. Tap to dismiss. Under Reduce Motion the scene
/// is its poster frame, paused.
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

    @State private var scene: EventSKScene
    @State private var slammed = false

    init(event: GameEvent, still: Bool, dismiss: @escaping () -> Void) {
        self.event = event
        self.still = still
        self.dismiss = dismiss
        _scene = State(initialValue: EventSKScene.make(event: event, still: still))
        _slammed = State(initialValue: still)
    }

    private var title: String { EventText.title(event) }
    private var subtitle: String { EventText.subtitle(event) }

    var body: some View {
        ZStack(alignment: .top) {
            SpriteView(scene: scene, options: [.ignoresSiblingOrder])
                .ignoresSafeArea()
            Headline(title: title, subtitle: subtitle, slammed: slammed)
        }
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(subtitle)")
        .accessibilityHint("Tap to dismiss")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("event.overlay")
        .onAppear {
            guard !still else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.45).delay(0.05)) { slammed = true }
        }
        .onDisappear { scene.tearDown() }
        .task(id: event) {
            try? await Task.sleep(for: .seconds(event.kind.duration))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }
}

/// The headline: heavy, tilted, bone white over a blood shadow with an ember
/// glow, slamming in from large. The line under it names the players.
private struct Headline: View {
    let title: String
    let subtitle: String
    let slammed: Bool

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Text(title)
                    .foregroundStyle(Color(Metal.bloodBright))
                    .offset(x: 5, y: 6)
                Text(title)
                    .foregroundStyle(Color(Metal.bone))
                    .shadow(color: .black, radius: 0, x: 2, y: 2)
                    .shadow(color: .black, radius: 0, x: -2, y: -2)
            }
            .font(.system(size: 62, weight: .black, design: .default))
            .textCase(.uppercase)
            .tracking(-1)
            .minimumScaleFactor(0.45)
            .lineLimit(1)
            .rotationEffect(.degrees(-4))
            .shadow(color: Color(Metal.ember).opacity(0.9), radius: 22)
            .shadow(color: .black.opacity(0.9), radius: 6, x: 0, y: 8)
            .scaleEffect(slammed ? 1 : 3.2)
            .opacity(slammed ? 1 : 0)
            Text(subtitle)
                .font(.system(.title2, design: .rounded, weight: .heavy))
                .foregroundStyle(Color(Metal.bone))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.55), in: Capsule())
                .shadow(color: .black.opacity(0.8), radius: 6, x: 0, y: 4)
                .opacity(slammed ? 1 : 0)
                .offset(y: slammed ? 0 : 24)
        }
        .padding(.horizontal, 20)
        .padding(.top, 70)
        .frame(maxWidth: .infinity)
    }
}

extension EventSKScene {
    static func make(event: GameEvent, still: Bool) -> EventSKScene {
        switch event.kind {
        case .holeInOne: HoleInOneScene(event: event, still: still)
        case .albatross: AlbatrossScene(event: event, still: still)
        case .eagle: EagleScene(event: event, still: still)
        case .greenie: GreenieScene(event: event, still: still)
        case .wadTaken: WadScene(event: event, still: still)
        case .skinWon: SkinScene(event: event, still: still)
        case .wolfHoleWon: WolfScene(event: event, still: still)
        case .snowman: SnowmanScene(event: event, still: still)
        case .birdie: BirdieScene(event: event, still: still)
        }
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
