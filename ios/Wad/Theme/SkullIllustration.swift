import SwiftUI

/// A skull over two crossed flagsticks, in flames, drawn with paths. For the
/// empty states.
struct SkullIllustration: View {
    var body: some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * width, y: y * height) }

            // The ember glow behind everything.
            let glowCenter = point(0.5, 0.78)
            context.fill(
                Path(ellipseIn: CGRect(x: 0, y: height * 0.25, width: width, height: height * 0.8)),
                with: .radialGradient(
                    Gradient(colors: [Theme.Palette.ember.opacity(0.45), Theme.Palette.ember.opacity(0)]),
                    center: glowCenter, startRadius: 0, endRadius: width * 0.5
                )
            )

            // The flagsticks, crossed like bones, with their flags up.
            let stickWidth = max(3, width * 0.028)
            for sign in [CGFloat(-1), 1] {
                let bottom = point(0.5 + sign * 0.42, 0.9)
                let top = point(0.5 - sign * 0.36, 0.06)
                var stick = Path()
                stick.move(to: bottom)
                stick.addLine(to: top)
                context.stroke(stick, with: .color(Theme.Palette.charcoal), style: StrokeStyle(lineWidth: stickWidth + 3, lineCap: .round))
                context.stroke(stick, with: .color(Theme.Palette.bone), style: StrokeStyle(lineWidth: stickWidth, lineCap: .round))

                var flag = Path()
                flag.move(to: top)
                flag.addLine(to: CGPoint(x: top.x - sign * width * 0.2, y: top.y + height * 0.07))
                flag.addLine(to: CGPoint(x: top.x, y: top.y + height * 0.15))
                flag.closeSubpath()
                context.fill(flag, with: .color(Theme.Palette.blood))
            }

            // Flames, rising behind the jaw.
            let tongues: [(x: CGFloat, w: CGFloat, tip: CGFloat)] = [
                (0.22, 0.14, 0.52), (0.36, 0.16, 0.38), (0.5, 0.2, 0.3), (0.64, 0.16, 0.4), (0.78, 0.14, 0.55),
            ]
            for (x, w, tip) in tongues {
                context.fill(flame(x: x, width: w, tip: tip, base: 0.98, point: point), with: .color(Theme.Palette.crimson))
                context.fill(flame(x: x, width: w * 0.5, tip: tip + 0.2, base: 0.98, point: point), with: .color(Theme.Palette.ember))
            }

            // The skull: cranium, cheekbones and jaw in one outline.
            var skull = Path()
            skull.move(to: point(0.5, 0.1))
            skull.addCurve(to: point(0.78, 0.42), control1: point(0.7, 0.1), control2: point(0.78, 0.26))
            skull.addCurve(to: point(0.66, 0.58), control1: point(0.78, 0.5), control2: point(0.72, 0.56))
            skull.addCurve(to: point(0.6, 0.76), control1: point(0.63, 0.62), control2: point(0.63, 0.72))
            skull.addCurve(to: point(0.4, 0.76), control1: point(0.56, 0.82), control2: point(0.44, 0.82))
            skull.addCurve(to: point(0.34, 0.58), control1: point(0.37, 0.72), control2: point(0.37, 0.62))
            skull.addCurve(to: point(0.22, 0.42), control1: point(0.28, 0.56), control2: point(0.22, 0.5))
            skull.addCurve(to: point(0.5, 0.1), control1: point(0.22, 0.26), control2: point(0.3, 0.1))
            skull.closeSubpath()
            context.stroke(skull, with: .color(Theme.Palette.charcoal), lineWidth: 4)
            context.fill(skull, with: .color(Theme.Palette.bone))

            // Eye sockets with an ember in each.
            for sign in [CGFloat(-1), 1] {
                let socket = CGRect(
                    origin: point(0.5 + sign * 0.1 - 0.08, 0.37),
                    size: CGSize(width: width * 0.15, height: height * 0.15)
                )
                context.fill(Path(ellipseIn: socket), with: .color(Theme.Palette.charcoal))
                let ember = CGRect(
                    origin: point(0.5 + sign * 0.1 - 0.03, 0.44),
                    size: CGSize(width: width * 0.06, height: height * 0.06)
                )
                context.fill(Path(ellipseIn: ember.insetBy(dx: -width * 0.02, dy: -height * 0.02)), with: .color(Theme.Palette.ember.opacity(0.35)))
                context.fill(Path(ellipseIn: ember), with: .color(Theme.Palette.ember))
            }

            // The nose.
            var nose = Path()
            nose.move(to: point(0.5, 0.5))
            nose.addLine(to: point(0.465, 0.59))
            nose.addQuadCurve(to: point(0.535, 0.59), control: point(0.5, 0.63))
            nose.closeSubpath()
            context.fill(nose, with: .color(Theme.Palette.charcoal))

            // Teeth: the gaps between them.
            let teeth = Path(roundedRect: CGRect(origin: point(0.38, 0.64), size: CGSize(width: width * 0.24, height: height * 0.11)), cornerRadius: 3)
            context.stroke(teeth, with: .color(Theme.Palette.charcoal), lineWidth: 1.5)
            for gap in 1...5 {
                let x = 0.38 + 0.24 * CGFloat(gap) / 6
                var line = Path()
                line.move(to: point(x, 0.64))
                line.addLine(to: point(x, 0.75))
                context.stroke(line, with: .color(Theme.Palette.charcoal), lineWidth: 1.5)
            }
            var bite = Path()
            bite.move(to: point(0.38, 0.695))
            bite.addLine(to: point(0.62, 0.695))
            context.stroke(bite, with: .color(Theme.Palette.charcoal), lineWidth: 2)

            // A crack across the cranium.
            var crack = Path()
            crack.move(to: point(0.58, 0.12))
            crack.addLine(to: point(0.62, 0.2))
            crack.addLine(to: point(0.58, 0.25))
            crack.addLine(to: point(0.63, 0.33))
            context.stroke(crack, with: .color(Theme.Palette.charcoal), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .aspectRatio(1.25, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// A tongue of flame: up from the base on one side, to the tip, down the other.
    private func flame(
        x: CGFloat, width: CGFloat, tip: CGFloat, base: CGFloat, point: (CGFloat, CGFloat) -> CGPoint
    ) -> Path {
        var path = Path()
        path.move(to: point(x - width / 2, base))
        path.addCurve(
            to: point(x + width * 0.1, tip),
            control1: point(x - width / 2, base - (base - tip) * 0.5),
            control2: point(x - width * 0.3, tip + (base - tip) * 0.25)
        )
        path.addCurve(
            to: point(x + width / 2, base),
            control1: point(x + width * 0.45, tip + (base - tip) * 0.3),
            control2: point(x + width / 2, base - (base - tip) * 0.4)
        )
        path.closeSubpath()
        return path
    }
}

/// A length of chain, link by link, for the edges that separate the parts of
/// a screen.
struct ChainDivider: View {
    var color = Theme.Palette.ash
    var height: CGFloat = 10

    var body: some View {
        Canvas { context, size in
            // Nothing to draw before the layout gives it a size.
            guard size.height > 0, size.width > 0 else { return }
            let linkLength = size.height * 1.9
            let linkHeight = size.height * 0.7
            let stroke = max(1.5, size.height * 0.18)
            let midY = size.height / 2
            var x: CGFloat = -linkLength / 2
            var flat = true
            while x < size.width {
                if flat {
                    let link = Path(
                        roundedRect: CGRect(x: x, y: midY - linkHeight / 2, width: linkLength, height: linkHeight),
                        cornerRadius: linkHeight / 2
                    )
                    context.stroke(link, with: .color(color), lineWidth: stroke)
                } else {
                    // A link seen edge on, between two flat ones.
                    let edge = Path(
                        roundedRect: CGRect(x: x + linkLength * 0.3, y: midY - stroke, width: linkLength * 0.4, height: stroke * 2),
                        cornerRadius: stroke
                    )
                    context.fill(edge, with: .color(color))
                }
                x += linkLength * 0.75
                flat.toggle()
            }
        }
        .frame(height: height)
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
                SkullIllustration()
                    .frame(maxWidth: 220)
                ChainDivider()
                    .frame(maxWidth: 220)
                    .padding(.bottom, Theme.Spacing.s)
                Text(title)
                    .font(Theme.Typography.display)
                    .foregroundStyle(Theme.Palette.bone)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(.body)
                    .foregroundStyle(Theme.Palette.ash)
                actions
                    .padding(.top, Theme.Spacing.s)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.xl * 2)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.Palette.charcoal.ignoresSafeArea())
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
