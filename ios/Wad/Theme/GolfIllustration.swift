import SwiftUI

/// A putting green with the flag in the hole and a ball beside it, drawn with
/// shapes. For the empty states.
struct GolfIllustration: View {
    var body: some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height

            // The sky behind the green.
            let sky = Path(ellipseIn: CGRect(x: width * 0.08, y: 0, width: width * 0.84, height: height * 0.92))
            context.fill(sky, with: .color(Theme.Palette.fairway.opacity(0.12)))

            // Fringe and green.
            let fringe = Path(ellipseIn: CGRect(x: 0, y: height * 0.58, width: width, height: height * 0.4))
            context.fill(fringe, with: .color(Theme.Palette.deepGreen))
            let green = Path(ellipseIn: CGRect(
                x: width * 0.06, y: height * 0.6, width: width * 0.88, height: height * 0.33
            ))
            context.fill(green, with: .color(Theme.Palette.fairway))

            // The hole.
            let holeCenter = CGPoint(x: width * 0.46, y: height * 0.76)
            let hole = Path(ellipseIn: CGRect(
                x: holeCenter.x - width * 0.06, y: holeCenter.y - height * 0.02,
                width: width * 0.12, height: height * 0.045
            ))
            context.fill(hole, with: .color(Theme.Palette.deepGreen))

            // The flagstick and the flag.
            let stickWidth = max(2, width * 0.018)
            let stickTop = height * 0.1
            let stick = Path(roundedRect: CGRect(
                x: holeCenter.x - stickWidth / 2, y: stickTop,
                width: stickWidth, height: holeCenter.y - stickTop
            ), cornerRadius: stickWidth / 2)
            context.fill(stick, with: .color(Theme.Palette.onGreen))
            context.stroke(stick, with: .color(Theme.Palette.rule), lineWidth: 0.5)

            var flag = Path()
            flag.move(to: CGPoint(x: holeCenter.x + stickWidth / 2, y: stickTop + height * 0.01))
            flag.addLine(to: CGPoint(x: holeCenter.x + width * 0.3, y: stickTop + height * 0.1))
            flag.addLine(to: CGPoint(x: holeCenter.x + stickWidth / 2, y: stickTop + height * 0.2))
            flag.closeSubpath()
            context.fill(flag, with: .color(Theme.Palette.flagRed))

            // The ball.
            let ballSize = width * 0.075
            let ball = Path(ellipseIn: CGRect(
                x: width * 0.68, y: height * 0.74, width: ballSize, height: ballSize
            ))
            context.fill(ball, with: .color(.white))
            context.stroke(ball, with: .color(Theme.Palette.deepGreen.opacity(0.4)), lineWidth: 1)
        }
        .aspectRatio(1.25, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// A screen with nothing to show yet: the illustration, what is missing and
/// what to do about it.
struct EmptyStateView<Actions: View>: View {
    let title: String
    let message: String
    @ViewBuilder let actions: Actions

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                GolfIllustration()
                    .frame(maxWidth: 220)
                    .padding(.bottom, Theme.Spacing.s)
                Text(title)
                    .font(Theme.Typography.display)
                    .foregroundStyle(Theme.Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(.body)
                    .foregroundStyle(Theme.Palette.inkSecondary)
                actions
                    .padding(.top, Theme.Spacing.s)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.xl * 2)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.Palette.sand.ignoresSafeArea())
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(title: String, message: String) {
        self.init(title: title, message: message) { EmptyView() }
    }
}

#Preview {
    EmptyStateView(title: "No rounds yet", message: "Set up a course, the players and the games to start one.") {
        Button("New round") {}
            .buttonStyle(.primary)
    }
}
