import SwiftUI

// MARK: - Lists

extension View {
    /// A list or form on the sand background. Its rows get the card color with
    /// `themedRows()` on the content of the list.
    func themedList() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.Palette.sand.ignoresSafeArea())
            .foregroundStyle(Theme.Palette.ink)
    }

    /// For the rows of a themed list.
    func themedRows() -> some View {
        listRowBackground(Theme.Palette.card)
            .listRowSeparatorTint(Theme.Palette.rule)
    }

    /// For the rows of a themed list that stand out, with `onGreen` text.
    func emphasizedRows() -> some View {
        listRowBackground(Theme.Palette.deepGreen)
            .listRowSeparatorTint(Theme.Palette.onGreen.opacity(0.25))
    }
}

/// The header of a section of a list: small capitals, with a symbol if it helps.
struct SectionHeader: View {
    let title: String
    var systemImage: String?

    init(_ title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(Theme.Palette.fairway)
                    .accessibilityHidden(true)
            }
            Text(title)
                .textCase(.uppercase)
                .tracking(0.8)
        }
        .font(Theme.Typography.overline)
        .foregroundStyle(Theme.Palette.inkSecondary)
    }
}

/// The footer of a section of a list.
struct SectionFooter: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .foregroundStyle(Theme.Palette.inkSecondary)
    }
}

/// A labeled value whose value is readable on the card color: the system's
/// secondary color is too light for small text.
struct ThemedLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                configuration.label
                Spacer(minLength: Theme.Spacing.s)
                configuration.content
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                configuration.label
                configuration.content
                    .foregroundStyle(Theme.Palette.inkSecondary)
            }
        }
        .foregroundStyle(Theme.Palette.ink)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Cards

/// A surface for content outside of a list.
struct Card<Content: View>: View {
    var emphasized = false
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(emphasized ? Theme.Palette.onGreen : Theme.Palette.ink)
            .background(
                emphasized ? Theme.Palette.deepGreen : Theme.Palette.card,
                in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.Palette.rule, lineWidth: emphasized ? 0 : 1)
            }
    }
}

// MARK: - Pills and money

/// A short fact in a capsule, such as "Par 4" or "All settled".
struct StatPill: View {
    enum Tone {
        case neutral, brand, gold, warning, onGreen
    }

    let text: String
    var systemImage: String?
    var tone = Tone.neutral

    private var foreground: Color {
        switch tone {
        case .neutral: Theme.Palette.inkSecondary
        case .brand: Theme.Palette.fairway
        case .gold: Theme.Palette.gold
        case .warning: Theme.Palette.flagRed
        case .onGreen: Theme.Palette.onGreen
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(foreground.opacity(0.12), in: Capsule())
        .overlay { Capsule().strokeBorder(foreground.opacity(0.35), lineWidth: 1) }
    }
}

/// An amount with what it means in words or with its sign. Gold for money
/// won, red for money owed; the text always says which it is.
struct MoneyLabel: View {
    /// "Won $20.00", "Owes $1.00", "+$45.00".
    let text: String
    /// Positive is won, negative is owed.
    let cents: Int
    var font = Font.body.weight(.semibold)

    var body: some View {
        Text(text)
            .font(font)
            .monospacedDigit()
            .foregroundStyle(Theme.Palette.money(cents: cents))
    }
}

// MARK: - Buttons

/// The main action of a screen.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.m)
            .foregroundStyle(isEnabled ? Theme.Palette.onFairway : Theme.Palette.inkSecondary)
            .background(
                isEnabled ? Theme.Palette.fairway : Theme.Palette.rule,
                in: RoundedRectangle(cornerRadius: Theme.Radius.chip + 2, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// An action next to the main one.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.m)
            .foregroundStyle(isEnabled ? Theme.Palette.fairway : Theme.Palette.inkSecondary)
            .background(
                Theme.Palette.card,
                in: RoundedRectangle(cornerRadius: Theme.Radius.chip + 2, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.chip + 2, style: .continuous)
                    .strokeBorder(isEnabled ? Theme.Palette.fairway.opacity(0.5) : Theme.Palette.rule, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}
